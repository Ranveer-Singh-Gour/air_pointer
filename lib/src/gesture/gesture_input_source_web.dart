import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:air_pointer/src/boundary/canvas_input_source.dart';
import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:air_pointer/src/filter/one_euro_filter.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const double _kPinchThreshold = 0.05;
const double _kMinCutoff = 1.0;
const double _kBeta = 0.05;
const double _kDeadzonePx = 3.0;

// Pinned to avoid silent breakage when MediaPipe releases incompatible updates.
const String _kMediaPipeVersion = '0.10.21';
const String _kWasmPath =
    'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@$_kMediaPipeVersion/wasm';
const String _kModelPath =
    'https://storage.googleapis.com/mediapipe-models/'
    'hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';

final class GestureInputSource implements CanvasInputSource {
  GestureInputSource({this.onError});

  final void Function(Object, StackTrace)? onError;

  final StreamController<PointerInputEvent> _controller =
      StreamController.broadcast();

  web.Worker? _worker;
  web.HTMLVideoElement? _video;
  web.HTMLVideoElement? _previewVideo;
  String? _previewViewType;

  // Completes when the camera stream is live and the preview view is registered.
  final Completer<void> _cameraReady = Completer<void>();

  bool _initialized = false;
  bool _disposed = false;

  // Set while the worker is processing a frame; prevents flooding the worker.
  bool _workerBusy = false;

  bool _wasDown = false;
  Size _canvasSize = Size.zero;
  Offset _lastEmittedPosition = Offset.zero;

  int _frameCount = 0;
  double _prevTimestampMs = 0;
  int _lastSendMs = 0;  // wall-clock ms when the last frame was posted

  final OneEuroFilter _xFilter =
      OneEuroFilter(minCutoff: _kMinCutoff, beta: _kBeta);
  final OneEuroFilter _yFilter =
      OneEuroFilter(minCutoff: _kMinCutoff, beta: _kBeta);

  void updateCanvasSize(Size size) => _canvasSize = size;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;

    try {
      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..autoplay = true
        ..muted = true     // required by browsers for autoplay without a user gesture
        ..playsInline = true
        ..style.display = 'none';
      web.document.body?.appendChild(video);
      _video = video;

      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(video: true.toJS, audio: false.toJS),
          )
          .toDart;
      if (_disposed) return;

      video.srcObject = stream;
      await video.play().toDart;  // await — autoplay attribute alone is unreliable
      if (_disposed) return;

      // Camera is live. Register the preview view — this completes _cameraReady.
      _setupPreview(stream);

      // Spin up the inference worker. MediaPipe is loaded inside the worker
      // (via its own ES module import) so the main thread stays clean.
      _worker = web.Worker(
        'hand_tracker_worker.js'.toJS,
        web.WorkerOptions(type: 'module'),
      );
      _worker!.onmessage = _onWorkerMessage.toJS;
      _worker!.onerror = ((web.Event _) {
        const msg =
            'hand_tracker_worker.js failed to load or threw an uncaught error.';
        onError?.call(StateError(msg), StackTrace.current);
      }).toJS;

      _worker!.postMessage(
        {'type': 'init', 'wasmPath': _kWasmPath, 'modelPath': _kModelPath}
            .jsify()!,
      );
      // The rAF capture loop starts when the worker posts 'ready'.
    } catch (e, st) {
      _initialized = false;
      _worker?.terminate();
      _worker = null;
      _video?.remove();
      _video = null;
      if (!_cameraReady.isCompleted) _cameraReady.completeError(e, st);
      onError?.call(e, st);
    }
  }

  void _onWorkerMessage(web.MessageEvent event) {
    if (_disposed) return;
    final raw = event.data.dartify();
    if (raw is! Map) return;
    final type = raw['type'] as String?;

    switch (type) {
      case 'ready':
        // Worker finished loading MediaPipe — start capturing frames.
        web.window.requestAnimationFrame(_captureLoop.toJS);

      case 'landmarks':
        _workerBusy = false;
        final tsMs = (raw['timestampMs'] as num).toDouble();
        final workerLatencyMs = (raw['workerLatencyMs'] as num? ?? 0).toDouble();
        final roundTripMs = DateTime.now().millisecondsSinceEpoch - _lastSendMs;
        final hands = raw['hands'] as List?;

        // Latency instrument: log every 60 frames (~2 s at 30 fps).
        _frameCount++;
        if (_frameCount % 60 == 0) {
          debugPrint(
            '[air_pointer] frame=$_frameCount '
            'worker=${workerLatencyMs.toStringAsFixed(1)} ms '
            'round-trip=$roundTripMs ms',
          );
        }

        final dt = _prevTimestampMs > 0
            ? (tsMs - _prevTimestampMs) / 1000.0
            : 1.0 / 30.0;
        _prevTimestampMs = tsMs;

        if (hands == null || hands.isEmpty) {
          if (_wasDown) {
            _wasDown = false;
            _emit(CanvasUpEvent(position: _lastEmittedPosition));
          }
        } else {
          _processHand(hands[0] as List<Object?>, dt);
        }

      case 'error':
        final msg = raw['message'] as String? ?? 'Unknown worker error';
        debugPrint('[air_pointer] worker init error: $msg');
        onError?.call(StateError(msg), StackTrace.current);
    }
  }

  void _captureLoop(JSNumber timestamp) {
    if (_disposed || _video == null || _worker == null) return;

    // Always reschedule first so the loop survives even if we skip this frame.
    web.window.requestAnimationFrame(_captureLoop.toJS);

    if (_video!.readyState < 2 || _workerBusy) return;

    _workerBusy = true;
    final tsMs = timestamp.toDartDouble;

    // Capture the video frame as an ImageBitmap (GPU blit, effectively free).
    // Ownership is transferred to the worker — no copy is made.
    web.window.createImageBitmap(_video!).toDart.then(
      (bitmap) {
        if (_disposed || _worker == null) {
          bitmap.close();  // we own it and won't send it
          return;
        }
        // Build the message with setProperty so the ImageBitmap (a JSAny) is
        // embedded directly. jsify() is unreliable for non-primitive JSAny values.
        final msg = JSObject();
        msg.setProperty('type'.toJS, 'detect'.toJS);
        msg.setProperty('frame'.toJS, bitmap);
        msg.setProperty('timestampMs'.toJS, tsMs.toJS);

        _lastSendMs = DateTime.now().millisecondsSinceEpoch;
        _worker!.postMessage(msg, [bitmap as JSObject].toJS);
      },
      onError: (_) {
        _workerBusy = false;  // createImageBitmap failed; release lock
      },
    );
  }

  void _processHand(List<Object?> landmarks, double dt) {
    final thumb = landmarks[4] as Map<Object?, Object?>;
    final index = landmarks[8] as Map<Object?, Object?>;

    final tx = (thumb['x'] as num).toDouble();
    final ty = (thumb['y'] as num).toDouble();
    final ix = (index['x'] as num).toDouble();
    final iy = (index['y'] as num).toDouble();

    final dx = tx - ix;
    final dy = ty - iy;
    final pinchDist = math.sqrt(dx * dx + dy * dy);
    final isPinched = pinchDist < _kPinchThreshold;

    final rawX = 1.0 - ix;  // mirror front-camera x-axis
    final rawY = iy;

    final smoothX = _xFilter.filter(rawX, dt);
    final smoothY = _yFilter.filter(rawY, dt);

    final position = Offset(
      smoothX * _canvasSize.width,
      smoothY * _canvasSize.height,
    );

    if (!_wasDown && isPinched) {
      _wasDown = true;
      _lastEmittedPosition = position;
      _emit(CanvasDownEvent(position: position));
    } else if (_wasDown && !isPinched) {
      _wasDown = false;
      _emit(CanvasUpEvent(position: _lastEmittedPosition));
    } else if (_wasDown) {
      final delta = position - _lastEmittedPosition;
      if (delta.distance >= _kDeadzonePx) {
        _lastEmittedPosition = position;
        _emit(CanvasMoveEvent(position: position));
      }
    } else {
      _emit(CanvasHoverEvent(position: position));
    }
  }

  void _setupPreview(web.MediaStream stream) {
    final preview = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..muted = true
      ..playsInline = true
      ..srcObject = stream;
    preview.style
      ..width = '100%'
      ..height = '100%'
      ..transform = 'scaleX(-1)';  // mirror for natural self-view
    preview.style.setProperty('object-fit', 'cover');

    _previewVideo = preview;
    _previewViewType = 'air_pointer_camera_${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(
      _previewViewType!,
      (_) => _previewVideo!,
    );
    // Camera feed is live — FutureBuilder can show the preview widget.
    _cameraReady.complete();
  }

  /// Returns a widget that shows the live camera feed.
  ///
  /// Shows a dark placeholder while the camera is initialising. Call
  /// [initialize] before (or concurrently with) embedding this widget.
  Widget buildCameraPreview({double? width, double? height}) =>
      FutureBuilder<void>(
        future: _cameraReady.future,
        builder: (context, snapshot) {
          Widget inner;
          if (snapshot.hasError) {
            inner = const ColoredBox(
              color: Color(0xFF2D0000),
              child: Center(
                child: Text(
                  'Camera unavailable.\nCheck console for details.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
                ),
              ),
            );
          } else if (snapshot.connectionState == ConnectionState.done) {
            inner = HtmlElementView(viewType: _previewViewType!);
          } else {
            inner = const ColoredBox(
              color: Color(0xFF1C1C1E),
              child: Center(
                child: Text(
                  'Starting camera…',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 11),
                ),
              ),
            );
          }
          return SizedBox(width: width, height: height, child: inner);
        },
      );

  void _emit(PointerInputEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  @override
  Stream<PointerInputEvent> get events => _controller.stream;

  @override
  Widget buildSurface({required Widget child}) => child;

  @override
  void dispose() {
    _disposed = true;
    // Ask the worker to close itself gracefully, then hard-terminate.
    _worker?.postMessage({'type': 'dispose'}.jsify()!);
    _worker?.terminate();
    _worker = null;
    _previewVideo?.srcObject = null;
    _previewVideo = null;
    final video = _video;
    if (video != null) {
      final src = video.srcObject;
      if (src != null && src.isA<web.MediaStream>()) {
        final s = src as web.MediaStream;
        final tracks = s.getTracks();
        for (var i = 0; i < tracks.length; i++) {
          tracks[i].stop();
        }
      }
      video.srcObject = null;
      video.remove();
      _video = null;
    }
    unawaited(_controller.close());
  }
}
