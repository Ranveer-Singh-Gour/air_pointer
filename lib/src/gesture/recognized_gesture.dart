/// A discrete hand gesture classified by a native ML backend.
///
/// Values match the gesture categories produced by the `hand_detection` package
/// (which wraps a TFLite gesture classifier). On web, [GestureDebugInfo]
/// populates [GestureDebugInfo.detectedGesture] via the pure-Dart
/// [classifyGesture] function, which uses tip-vs-PIP landmark comparisons.
/// On native, the [LandmarkProvider] sets the value directly from its ML
/// classifier (e.g. `hand_detection`'s TFLite gesture model).
///
/// ## Mapping from `hand_detection`
/// | `hand_detection` category | [RecognizedGesture] value |
/// |---|---|
/// | `Gesture.none` | [none] |
/// | `Gesture.closedFist` | [closedFist] |
/// | `Gesture.openPalm` | [openPalm] |
/// | `Gesture.pointingUp` | [pointingUp] |
/// | `Gesture.thumbUp` | [thumbUp] |
/// | `Gesture.thumbDown` | [thumbDown] |
/// | `Gesture.victory` | [victory] |
/// | `Gesture.iLoveYou` | [iLoveYou] |
enum RecognizedGesture {
  /// No hand detected, or the classifier did not produce a confident result.
  none,

  /// All fingers curled into a closed fist. ✊
  closedFist,

  /// All fingers extended and spread. 🖐
  openPalm,

  /// Index finger extended, others curled. ☝
  pointingUp,

  /// Thumb extended upward, fingers curled. 👍
  thumbUp,

  /// Thumb extended downward, fingers curled. 👎
  thumbDown,

  /// Index and middle fingers extended in a V. ✌
  victory,

  /// Thumb, index, and pinky extended. 🤙
  iLoveYou,
}
