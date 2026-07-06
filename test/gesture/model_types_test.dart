import 'package:air_pointer/src/gesture/calibration_result.dart';
import 'package:air_pointer/src/gesture/gesture_phase.dart';
import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:air_pointer/src/gesture/hand_landmark_type.dart';
import 'package:air_pointer/src/gesture/landmark_provider.dart';
import 'package:air_pointer/src/gesture/recognized_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HandLandmarkPoint', () {
    test('stores coordinates and defaults visibility to 1.0', () {
      const p = HandLandmarkPoint(0.1, 0.2, 0.3);
      expect(p.x, 0.1);
      expect(p.y, 0.2);
      expect(p.z, 0.3);
      expect(p.visibility, 1.0);
    });

    test('accepts an explicit visibility', () {
      const p = HandLandmarkPoint(0, 0, 0, visibility: 0.25);
      expect(p.visibility, 0.25);
    });
  });

  group('HandLandmarkType', () {
    test('has the 21 MediaPipe landmarks in index order', () {
      expect(HandLandmarkType.values, hasLength(21));
      expect(HandLandmarkType.wrist.index, 0);
      expect(HandLandmarkType.thumbTip.index, 4);
      expect(HandLandmarkType.indexTip.index, 8);
      expect(HandLandmarkType.middleTip.index, 12);
      expect(HandLandmarkType.ringTip.index, 16);
      expect(HandLandmarkType.pinkyTip.index, 20);
    });

    test('getLandmark returns the point at the landmark index', () {
      final lms = List<HandLandmarkPoint>.generate(
        21,
        (i) => HandLandmarkPoint(i / 21, 0, 0),
      );
      expect(lms.getLandmark(HandLandmarkType.wrist), same(lms[0]));
      expect(lms.getLandmark(HandLandmarkType.indexTip), same(lms[8]));
    });

    test('skeleton connections are well-formed pairs', () {
      expect(handLandmarkConnections, isNotEmpty);
      for (final connection in handLandmarkConnections) {
        expect(connection, hasLength(2));
        expect(connection[0], isNot(connection[1]));
      }
    });
  });

  group('CalibrationResult', () {
    test('defaults match the documented factory thresholds', () {
      expect(CalibrationResult.defaults.pinchCloseThreshold, 0.05);
      expect(CalibrationResult.defaults.pinchOpenThreshold, 0.08);
    });

    test('rejects an open threshold at or below the close threshold', () {
      expect(
        () => CalibrationResult(
          pinchCloseThreshold: 0.08,
          pinchOpenThreshold: 0.05,
        ),
        throwsAssertionError,
      );
    });
  });

  group('GestureDebugInfo', () {
    test('defaults to an empty, untracked snapshot', () {
      const info = GestureDebugInfo(
        phase: GesturePhase.lost,
        pinchDistance: 0,
        landmarks: [],
      );
      expect(info.secondHandLandmarks, isEmpty);
      expect(info.worldLandmarks, isEmpty);
      expect(info.isTwoHandActive, isFalse);
      expect(info.handedness, Handedness.unknown);
      expect(info.detectedGesture, RecognizedGesture.none);
      expect(info.dwellProgress, 0.0);
      expect(info.isPointing, isFalse);
      expect(info.boundingBox, isNull);
    });
  });

  group('HandDetectionFrame', () {
    test('defaults to a no-hand frame with full confidence', () {
      const frame = HandDetectionFrame();
      expect(frame.landmarks, isEmpty);
      expect(frame.secondHandLandmarks, isEmpty);
      expect(frame.worldLandmarks, isEmpty);
      expect(frame.handedness, Handedness.unknown);
      expect(frame.detectedGesture, RecognizedGesture.none);
      expect(frame.gestureConfidence, 1.0);
      expect(frame.secondHandGestureConfidence, 1.0);
      expect(frame.boundingBox, isNull);
    });
  });

  group('RecognizedGesture', () {
    test('none is the first value so it is the natural default', () {
      expect(RecognizedGesture.values.first, RecognizedGesture.none);
    });
  });
}
