import 'package:air_pointer/src/gesture/gesture_classifier.dart';
import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:air_pointer/src/gesture/recognized_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Landmark builders
// ---------------------------------------------------------------------------

// Default: all 21 landmarks at (0.5, 0.5, 0).
// With all landmarks at the same y, tip.y == pip.y → NOT extended (curled).
List<HandLandmarkPoint> _base() =>
    List.generate(21, (_) => const HandLandmarkPoint(0.5, 0.5, 0));

// Extend a finger: tip.y set to 0.2 (well above pip.y 0.5 in screen coords).
List<HandLandmarkPoint> _extend(
  List<HandLandmarkPoint> lms,
  int tipIndex,
) {
  final copy = List<HandLandmarkPoint>.of(lms);
  copy[tipIndex] = HandLandmarkPoint(lms[tipIndex].x, 0.2, lms[tipIndex].z);
  return copy;
}

// Raise thumb tip above MCP (thumbUp) or below (thumbDown).
// thumbTip=4, thumbMcp=2.
List<HandLandmarkPoint> _thumbUp(List<HandLandmarkPoint> lms) {
  final copy = List<HandLandmarkPoint>.of(lms);
  copy[4] = const HandLandmarkPoint(0.5, 0.2, 0); // well above MCP y=0.5
  return copy;
}

List<HandLandmarkPoint> _thumbDown(List<HandLandmarkPoint> lms) {
  final copy = List<HandLandmarkPoint>.of(lms);
  copy[4] = const HandLandmarkPoint(0.5, 0.8, 0); // well below MCP y=0.5
  return copy;
}

// Raise thumb tip above CMC for iLoveYou thumb check.
// thumbTip=4, thumbCmc=1.  Default CMC y = 0.5.
List<HandLandmarkPoint> _thumbExtended(List<HandLandmarkPoint> lms) {
  final copy = List<HandLandmarkPoint>.of(lms);
  copy[4] = const HandLandmarkPoint(0.5, 0.2, 0); // above CMC y=0.5
  return copy;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('classifyGesture', () {
    test('returns none for null landmarks', () {
      expect(classifyGesture(null), RecognizedGesture.none);
    });

    test('returns none when fewer than 21 landmarks', () {
      expect(classifyGesture([const HandLandmarkPoint(0.5, 0.5, 0)]),
          RecognizedGesture.none);
    });

    test('closedFist — all fingers curled, thumb near MCP', () {
      // Default base: all at 0.5 → all curled; thumb tip at MCP y (gap = 0 < deadzone).
      expect(classifyGesture(_base()), RecognizedGesture.closedFist);
    });

    test('thumbUp — all fingers curled, thumb tip well above MCP', () {
      expect(classifyGesture(_thumbUp(_base())), RecognizedGesture.thumbUp);
    });

    test('thumbDown — all fingers curled, thumb tip well below MCP', () {
      expect(classifyGesture(_thumbDown(_base())), RecognizedGesture.thumbDown);
    });

    test('openPalm — all four fingers extended', () {
      var lms = _base();
      lms = _extend(lms, 8);   // index tip
      lms = _extend(lms, 12);  // middle tip
      lms = _extend(lms, 16);  // ring tip
      lms = _extend(lms, 20);  // pinky tip
      expect(classifyGesture(lms), RecognizedGesture.openPalm);
    });

    test('victory — index + middle extended, ring + pinky curled', () {
      var lms = _base();
      lms = _extend(lms, 8);   // index tip
      lms = _extend(lms, 12);  // middle tip
      expect(classifyGesture(lms), RecognizedGesture.victory);
    });

    test('pointingUp — only index extended', () {
      expect(classifyGesture(_extend(_base(), 8)), RecognizedGesture.pointingUp);
    });

    test('iLoveYou — thumb + index + pinky extended, middle + ring curled', () {
      var lms = _base();
      lms = _thumbExtended(lms);  // thumb tip above CMC
      lms = _extend(lms, 8);      // index tip
      lms = _extend(lms, 20);     // pinky tip
      expect(classifyGesture(lms), RecognizedGesture.iLoveYou);
    });

    test('index + pinky extended but thumb NOT extended → not iLoveYou', () {
      // Without the thumb check, index+pinky alone would be ambiguous.
      var lms = _base();
      lms = _extend(lms, 8);   // index tip
      lms = _extend(lms, 20);  // pinky tip
      // Thumb stays at 0.5 (not above CMC y=0.5), so thumbExt = false.
      // No match in the classifier → none.
      expect(classifyGesture(lms), RecognizedGesture.none);
    });

    test('thumbDown deadzone — thumb tip just below MCP (< 0.05 gap) → closedFist', () {
      final lms = List<HandLandmarkPoint>.of(_base());
      // MCP (index 2) at y=0.5. Thumb tip at y=0.54 → gap = 0.04 < 0.05 deadzone.
      lms[4] = const HandLandmarkPoint(0.5, 0.54, 0);
      expect(classifyGesture(lms), RecognizedGesture.closedFist);
    });

    test('thumbUp deadzone — thumb tip just above MCP (< 0.05 gap) → closedFist', () {
      final lms = List<HandLandmarkPoint>.of(_base());
      // MCP (index 2) at y=0.5. Thumb tip at y=0.46 → gap = 0.04 < 0.05 deadzone.
      lms[4] = const HandLandmarkPoint(0.5, 0.46, 0);
      expect(classifyGesture(lms), RecognizedGesture.closedFist);
    });

    test('unrecognised combination → none', () {
      // Ring only extended — doesn't match any defined gesture.
      expect(classifyGesture(_extend(_base(), 16)), RecognizedGesture.none);
    });
  });
}
