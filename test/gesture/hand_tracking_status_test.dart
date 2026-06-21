import 'dart:async';

import 'package:air_pointer/src/gesture/gesture_input_source_native.dart';
import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:air_pointer/src/gesture/hand_tracking_status.dart';
import 'package:air_pointer/src/gesture/landmark_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Mock provider
// ---------------------------------------------------------------------------

class _MockProvider implements LandmarkProvider {
  final _ctrl = StreamController<HandDetectionFrame>.broadcast();

  @override
  Stream<HandDetectionFrame> get frames => _ctrl.stream;

  @override
  Widget buildPreview({double? width, double? height}) => const SizedBox();

  @override
  void dispose() => unawaited(_ctrl.close());

  void push(HandDetectionFrame frame) => _ctrl.add(frame);
  void pushError(Object error) => _ctrl.addError(error);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Open hand: thumb–index distance 0.2 (above open threshold 0.08).
HandDetectionFrame _openFrame() {
  final lms = List<HandLandmarkPoint>.generate(
    21,
    (_) => const HandLandmarkPoint(0.5, 0.5, 0),
  );
  lms[4] = const HandLandmarkPoint(0.4, 0.5, 0); // thumb tip
  lms[8] = const HandLandmarkPoint(0.6, 0.5, 0); // index tip
  return HandDetectionFrame(landmarks: lms);
}

const _noHand = HandDetectionFrame();
const _size = Size(800, 600);

GestureInputSource _source(_MockProvider provider) {
  final src = GestureInputSource(landmarkProvider: provider);
  src.updateCanvasSize(_size);
  return src;
}

Future<void> _push(_MockProvider p, HandDetectionFrame f, int n) async {
  for (var i = 0; i < n; i++) {
    p.push(f);
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HandTrackingStatus stream — native source', () {
    test('no provider — statusStream emits nothing on initialize', () async {
      final src = GestureInputSource()..updateCanvasSize(_size);
      final statuses = <HandTrackingStatus>[];
      final sub = src.statusStream.listen(statuses.add);
      await src.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(statuses, isEmpty);
      await sub.cancel();
      src.dispose();
    });

    test('emits HandTrackingInitializing on initialize()', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);

      await src.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(statuses, [isA<HandTrackingInitializing>()]);
      src.dispose();
    });

    test('emits HandTrackingCameraReady on first frame', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      provider.push(_openFrame());
      await Future<void>.delayed(Duration.zero);

      expect(statuses[0], isA<HandTrackingInitializing>());
      expect(statuses[1], isA<HandTrackingCameraReady>());
      src.dispose();
    });

    test('emits HandTrackingCameraReady only once', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      await _push(provider, _openFrame(), 6);

      expect(statuses.whereType<HandTrackingCameraReady>().length, 1);
      src.dispose();
    });

    test('emits HandTrackingTracking after 3 confirmed frames', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      await _push(provider, _openFrame(), 3);

      expect(statuses.whereType<HandTrackingTracking>(), isNotEmpty);
      src.dispose();
    });

    test('emits HandTrackingLost on first no-hand frame after hovering', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      await _push(provider, _openFrame(), 3);
      expect(statuses.whereType<HandTrackingTracking>(), isNotEmpty);

      provider.push(_noHand);
      await Future<void>.delayed(Duration.zero);

      expect(statuses.whereType<HandTrackingLost>(), isNotEmpty);
      src.dispose();
    });

    test('emits HandTrackingTracking again on hand re-entry during grace', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      await _push(provider, _openFrame(), 3);

      // First exit — enters grace, emits lost
      provider.push(_noHand);
      await Future<void>.delayed(Duration.zero);
      expect(statuses.whereType<HandTrackingLost>(), isNotEmpty);

      final trackingCountBefore = statuses.whereType<HandTrackingTracking>().length;

      // Re-enter during grace — recovers directly to hovering
      provider.push(_openFrame());
      await Future<void>.delayed(Duration.zero);

      expect(
        statuses.whereType<HandTrackingTracking>().length,
        greaterThan(trackingCountBefore),
      );
      src.dispose();
    });

    test('full tracking → lost → tracking → lost cycle', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      // Session 1
      await _push(provider, _openFrame(), 3);
      // Exit and wait for full grace expiry (graceFrames = 5)
      await _push(provider, _noHand, 5);
      // Session 2 (fresh re-acquisition, 3 frames)
      await _push(provider, _openFrame(), 3);
      // Exit again
      provider.push(_noHand);
      await Future<void>.delayed(Duration.zero);

      expect(statuses.whereType<HandTrackingTracking>().length, 2);
      expect(statuses.whereType<HandTrackingLost>().length, 2);
      src.dispose();
    });

    test('emits HandTrackingError on provider error', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      provider.pushError(StateError('camera disconnected'));
      await Future<void>.delayed(Duration.zero);

      expect(statuses.whereType<HandTrackingError>(), isNotEmpty);
      final err = statuses.whereType<HandTrackingError>().first;
      expect(err.error, isA<StateError>());
      src.dispose();
    });

    test('no tracking or lost emitted after error', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      // Confirm tracking
      await _push(provider, _openFrame(), 3);
      expect(statuses.whereType<HandTrackingTracking>(), isNotEmpty);

      // Trigger error
      provider.pushError(StateError('sensor failure'));
      await Future<void>.delayed(Duration.zero);
      expect(statuses.whereType<HandTrackingError>(), isNotEmpty);

      final countAfterError = statuses.length;

      // Post-error frames must not emit any further status
      await _push(provider, _noHand, 6);
      await _push(provider, _openFrame(), 3);

      expect(statuses.length, equals(countAfterError));
      src.dispose();
    });

    test('status order: initializing → cameraReady → tracking', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);
      await src.initialize();

      await _push(provider, _openFrame(), 3);

      expect(statuses[0], isA<HandTrackingInitializing>());
      expect(statuses[1], isA<HandTrackingCameraReady>());
      expect(statuses.last, isA<HandTrackingTracking>());
      src.dispose();
    });

    test('double initialize() is idempotent — no duplicate subscriptions', () async {
      final provider = _MockProvider();
      final src = _source(provider);
      final statuses = <HandTrackingStatus>[];
      src.statusStream.listen(statuses.add);

      await src.initialize();
      await src.initialize(); // second call must be a no-op
      await Future<void>.delayed(Duration.zero);

      // Only one HandTrackingInitializing emitted.
      expect(statuses.whereType<HandTrackingInitializing>().length, 1);

      // Bring recognizer to hovering (3-frame acquisition gate).
      await _push(provider, _openFrame(), 3);

      // Subscribe, then push one frame. A duplicate listener routes each push
      // through _onFrame twice — doubling events per push. Single listener = 1.
      final events = <Object>[];
      final sub = src.events.listen(events.add);
      provider.push(_openFrame());
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      await sub.cancel();
      src.dispose();
    });
  });
}
