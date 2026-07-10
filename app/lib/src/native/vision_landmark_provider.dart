import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// [LandmarkProvider] backed by macOS's Vision framework
/// (`VNDetectHumanHandPoseRequest`), running natively in
/// `CameraHandTracker.swift`.
///
/// Camera lifecycle is tied to whether [frames] has a subscriber: the native
/// side's `HandLandmarkEventChannel.onListen`/`onCancel` start/stop the
/// capture session automatically (mirrors how `GestureInputSource.initialize()`
/// subscribing to [frames] is what should turn the camera on).
class VisionLandmarkProvider implements LandmarkProvider {
  VisionLandmarkProvider() {
    _frameSub = _eventChannel.receiveBroadcastStream().listen(
      (dynamic raw) => _controller.add(_parseFrame(raw as Map<Object?, Object?>)),
      onError: (Object e, StackTrace st) => _controller.addError(e, st),
    );
  }

  static const _eventChannel = EventChannel('air_pointer_app/hand_landmarks');
  static const _previewViewType = 'air_pointer_app/camera_preview';

  final StreamController<HandDetectionFrame> _controller = StreamController.broadcast();
  StreamSubscription<dynamic>? _frameSub;

  @override
  Stream<HandDetectionFrame> get frames => _controller.stream;

  @override
  Widget buildPreview({double? width, double? height}) => SizedBox(
        width: width,
        height: height,
        child: const AppKitView(viewType: _previewViewType),
      );

  @override
  void dispose() {
    unawaited(_frameSub?.cancel());
    unawaited(_controller.close());
  }

  static HandDetectionFrame _parseFrame(Map<Object?, Object?> raw) {
    final hands = raw['hands'] as List<Object?>? ?? const [];
    if (hands.isEmpty) return const HandDetectionFrame();

    final first = _parseHand(hands[0] as List<Object?>);
    final second = hands.length >= 2 ? _parseHand(hands[1] as List<Object?>) : const <HandLandmarkPoint>[];

    return HandDetectionFrame(
      landmarks: first,
      secondHandLandmarks: second,
      // Vision doesn't classify left/right, provide world-space (metric)
      // landmarks, or discrete gestures itself — `GestureInputSource` reads
      // `detectedGesture` straight off this frame rather than computing it,
      // so this backend has to run the package's own tip-vs-PIP classifier
      // over the raw landmarks here to get any CanvasGestureEvent at all.
      detectedGesture: classifyGesture(first),
      secondHandGesture: second.isEmpty ? RecognizedGesture.none : classifyGesture(second),
    );
  }

  static List<HandLandmarkPoint> _parseHand(List<Object?> points) => points
      .map((p) {
        final m = p as Map<Object?, Object?>;
        return HandLandmarkPoint(
          m['x']! as double,
          m['y']! as double,
          0.0, // Vision's hand pose is 2D-only; no z/depth is provided.
          visibility: m['visibility']! as double,
        );
      })
      .toList();
}
