import 'package:air_pointer/src/gesture/hand_landmark_point.dart';
import 'package:air_pointer/src/gesture/hand_landmark_type.dart';
import 'package:air_pointer/src/gesture/recognized_gesture.dart';

// Minimum normalised-y gap between thumb tip and MCP required to classify
// thumbsUp / thumbsDown. Prevents a relaxed fist — where the thumb rests
// near the MCP — from triggering a false thumb-up or thumb-down.
const _thumbDeadzone = 0.05;

/// Classifies the hand pose in [landmarks] into a [RecognizedGesture].
///
/// Returns [RecognizedGesture.none] when [landmarks] is null or has fewer
/// than 21 points. The classifier uses normalised y-coordinates only
/// (y increases downward, matching MediaPipe's convention), so it is
/// orientation-agnostic about hand rotation in the image plane.
///
/// This function is used by [GestureInputSource] on web to populate
/// [GestureDebugInfo.detectedGesture] from raw MediaPipe landmarks.
RecognizedGesture classifyGesture(List<HandLandmarkPoint>? landmarks) {
  if (landmarks == null || landmarks.length < 21) return RecognizedGesture.none;

  final thumbTip = landmarks.getLandmark(HandLandmarkType.thumbTip);
  final thumbMcp = landmarks.getLandmark(HandLandmarkType.thumbMcp);
  final thumbCmc = landmarks.getLandmark(HandLandmarkType.thumbCmc);
  final indexTip = landmarks.getLandmark(HandLandmarkType.indexTip);
  final indexPip = landmarks.getLandmark(HandLandmarkType.indexPip);
  final middleTip = landmarks.getLandmark(HandLandmarkType.middleTip);
  final middlePip = landmarks.getLandmark(HandLandmarkType.middlePip);
  final ringTip = landmarks.getLandmark(HandLandmarkType.ringTip);
  final ringPip = landmarks.getLandmark(HandLandmarkType.ringPip);
  final pinkyTip = landmarks.getLandmark(HandLandmarkType.pinkyTip);
  final pinkyPip = landmarks.getLandmark(HandLandmarkType.pinkyPip);

  // Extended = tip is higher in frame (lower y) than the PIP joint.
  final indexExt = indexTip.y < indexPip.y;
  final middleExt = middleTip.y < middlePip.y;
  final ringExt = ringTip.y < ringPip.y;
  final pinkyExt = pinkyTip.y < pinkyPip.y;
  final fourCurled = !indexExt && !middleExt && !ringExt && !pinkyExt;

  // When all four fingers are curled, the thumb direction distinguishes
  // thumbsUp, thumbsDown, and closedFist.
  if (fourCurled) {
    if (thumbTip.y < thumbMcp.y - _thumbDeadzone) return RecognizedGesture.thumbUp;
    if (thumbTip.y > thumbMcp.y + _thumbDeadzone) return RecognizedGesture.thumbDown;
    return RecognizedGesture.closedFist;
  }

  if (indexExt && middleExt && ringExt && pinkyExt) return RecognizedGesture.openPalm;

  // iLoveYou: thumb, index, and pinky extended; middle and ring curled.
  // Thumb-extended check: tip above the CMC (base of thumb at wrist).
  final thumbExt = thumbTip.y < thumbCmc.y;
  if (thumbExt && indexExt && !middleExt && !ringExt && pinkyExt) {
    return RecognizedGesture.iLoveYou;
  }

  if (indexExt && middleExt && !ringExt && !pinkyExt) return RecognizedGesture.victory;
  if (indexExt && !middleExt && !ringExt && !pinkyExt) return RecognizedGesture.pointingUp;

  return RecognizedGesture.none;
}
