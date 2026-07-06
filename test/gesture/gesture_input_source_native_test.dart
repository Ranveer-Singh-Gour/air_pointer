import 'dart:async';

import 'package:air_pointer/src/events/pointer_input_event.dart';
import 'package:air_pointer/src/gesture/gesture_input_source_native.dart';
import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:air_pointer/src/gesture/hand_tracking_status.dart';
import 'package:air_pointer/src/gesture/landmark_provider.dart';
import 'package:air_pointer/src/gesture/recognized_gesture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(800, 600);

// 21 landmarks with all points at (0.5, 0.5, 0) except thumb tip [4] and
// index tip [8], mirroring the helpers in hand_gesture_recognizer_test.dart.
List<HandLandmarkPoint> _hand({required double thumbX, required double indexX}) {
  final lms = List<HandLandmarkPoint>.generate(
    21,
    (_) => const HandLandmarkPoint(0.5, 0.5, 0),
  );
  lms[4] = HandLandmarkPoint(thumbX, 0.5, 0);
  lms[8] = HandLandmarkPoint(indexX, 0.5, 0);
  return lms;
}

// Open hand: thumb–index distance = 0.2, well above open threshold (0.08).
List<HandLandmarkPoint> _open() => _hand(thumbX: 0.4, indexX: 0.6);

// Pinched hand: thumb–index distance = 0.02, below close threshold (0.05).
List<HandLandmarkPoint> _pinch() => _hand(thumbX: 0.49, indexX: 0.5);

final class _FakeProvider implements LandmarkProvider {
  final StreamController<HandDetectionFrame> _ctrl =
      StreamController<HandDetectionFrame>.broadcast();
  bool disposed = false;

  @override
  Stream<HandDetectionFrame> get frames => _ctrl.stream;

  @override
  Widget buildPreview({double? width, double? height}) =>
      SizedBox(width: width, height: height);

  @override
  void dispose() {
    disposed = true;
    unawaited(_ctrl.close());
  }

  void add(HandDetectionFrame frame) => _ctrl.add(frame);

  void addError(Object error) => _ctrl.addError(error);
}

// Deliver [frames] through the provider and let the event loop drain.
Future<void> _pump(_FakeProvider provider, List<HandDetectionFrame> frames) async {
  frames.forEach(provider.add);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('GestureInputSource (native)', () {
    test('initialize without a provider is a no-op', () async {
      final source = GestureInputSource();
      final statuses = <HandTrackingStatus>[];
      source.statusStream.listen(statuses.add);

      await source.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(statuses, isEmpty);
      source.dispose();
    });

    test('emits initializing, then cameraReady on the first frame', () async {
      final provider = _FakeProvider();
      final source = GestureInputSource(landmarkProvider: provider);
      final statuses = <HandTrackingStatus>[];
      source.statusStream.listen(statuses.add);

      await source.initialize();
      await _pump(provider, [const HandDetectionFrame()]);

      expect(statuses, hasLength(2));
      expect(statuses[0], isA<HandTrackingInitializing>());
      expect(statuses[1], isA<HandTrackingCameraReady>());
      source.dispose();
    });

    test('emits hover events and tracking status after acquisition', () async {
      final provider = _FakeProvider();
      final source = GestureInputSource(landmarkProvider: provider)
        ..updateCanvasSize(_size);
      final events = <PointerInputEvent>[];
      final statuses = <HandTrackingStatus>[];
      source.events.listen(events.add);
      source.statusStream.listen(statuses.add);

      await source.initialize();
      // Default acquireFrames is 3 consecutive hand frames.
      await _pump(provider, [
        HandDetectionFrame(landmarks: _open()),
        HandDetectionFrame(landmarks: _open()),
        HandDetectionFrame(landmarks: _open()),
      ]);

      expect(events.whereType<CanvasHoverEvent>(), isNotEmpty);
      expect(statuses.whereType<HandTrackingTracking>(), hasLength(1));
      source.dispose();
    });

    test('pinch after acquisition emits CanvasDownEvent', () async {
      final provider = _FakeProvider();
      final source = GestureInputSource(landmarkProvider: provider)
        ..updateCanvasSize(_size);
      final events = <PointerInputEvent>[];
      source.events.listen(events.add);

      await source.initialize();
      await _pump(provider, [
        HandDetectionFrame(landmarks: _open()),
        HandDetectionFrame(landmarks: _open()),
        HandDetectionFrame(landmarks: _open()),
        HandDetectionFrame(landmarks: _pinch()),
      ]);

      expect(events.whereType<CanvasDownEvent>(), hasLength(1));
      source.dispose();
    });

    test('gesture is emitted once on its leading edge', () async {
      final provider = _FakeProvider();
      final source = GestureInputSource(landmarkProvider: provider);
      final events = <PointerInputEvent>[];
      source.events.listen(events.add);

      await source.initialize();
      await _pump(provider, [
        const HandDetectionFrame(
          detectedGesture: RecognizedGesture.thumbUp,
          gestureConfidence: 0.9,
        ),
        const HandDetectionFrame(detectedGesture: RecognizedGesture.thumbUp),
      ]);

      final gestures = events.whereType<CanvasGestureEvent>().toList();
      expect(gestures, hasLength(1));
      expect(gestures.single.gesture, RecognizedGesture.thumbUp);
      expect(gestures.single.confidence, 0.9);
      expect(gestures.single.isSecondHand, isFalse);
      source.dispose();
    });

    test('second-hand gesture is flagged isSecondHand', () async {
      final provider = _FakeProvider();
      final source = GestureInputSource(landmarkProvider: provider);
      final events = <PointerInputEvent>[];
      source.events.listen(events.add);

      await source.initialize();
      await _pump(provider, [
        const HandDetectionFrame(secondHandGesture: RecognizedGesture.victory),
      ]);

      final gestures = events.whereType<CanvasGestureEvent>().toList();
      expect(gestures, hasLength(1));
      expect(gestures.single.gesture, RecognizedGesture.victory);
      expect(gestures.single.isSecondHand, isTrue);
      source.dispose();
    });

    test('provider error surfaces via onError and a single error status',
        () async {
      final provider = _FakeProvider();
      final errors = <Object>[];
      final source = GestureInputSource(
        landmarkProvider: provider,
        onError: (e, st) => errors.add(e),
      );
      final statuses = <HandTrackingStatus>[];
      source.statusStream.listen(statuses.add);

      await source.initialize();
      provider.addError(StateError('camera failed'));
      provider.addError(StateError('camera failed again'));
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(2));
      expect(statuses.whereType<HandTrackingError>(), hasLength(1));
      source.dispose();
    });

    test('initialize is idempotent — frames are not processed twice', () async {
      final provider = _FakeProvider();
      final source = GestureInputSource(landmarkProvider: provider);
      final events = <PointerInputEvent>[];
      source.events.listen(events.add);

      await source.initialize();
      await source.initialize();
      await _pump(provider, [
        const HandDetectionFrame(detectedGesture: RecognizedGesture.openPalm),
      ]);

      expect(events.whereType<CanvasGestureEvent>(), hasLength(1));
      source.dispose();
    });

    test('dispose disposes the provider and closes the event stream', () async {
      final provider = _FakeProvider();
      final source = GestureInputSource(landmarkProvider: provider);
      await source.initialize();

      final done = source.events.drain<void>();
      source.dispose();

      expect(provider.disposed, isTrue);
      await expectLater(done, completes);
    });

    test('buildCameraPreview delegates to the provider when present', () {
      final provider = _FakeProvider();
      final source = GestureInputSource(landmarkProvider: provider);
      final preview = source.buildCameraPreview(width: 100, height: 50);
      expect(preview, isA<SizedBox>());
      expect((preview as SizedBox).width, 100);
      source.dispose();
    });

    test('buildCameraPreview falls back to an empty box without a provider',
        () {
      final source = GestureInputSource();
      final preview = source.buildCameraPreview();
      expect(preview, isA<SizedBox>());
      source.dispose();
    });

    test('buildSurface returns the child unchanged', () {
      final source = GestureInputSource();
      const child = Text('canvas', textDirection: TextDirection.ltr);
      expect(source.buildSurface(child: child), same(child));
      source.dispose();
    });
  });
}
