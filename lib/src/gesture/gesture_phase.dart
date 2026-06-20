import 'package:air_pointer/src/gesture/hand_landmark_point.dart';

/// Lifecycle state of the gesture recogniser's hand-tracking session.
enum GesturePhase {
  /// Hand appeared in frame; waiting for N consecutive frames to confirm.
  acquiring,

  /// Hand confirmed and tracked, no pinch active.
  hovering,

  /// Pinch gesture active — drag in progress.
  down,

  /// Hand disappeared; within the grace window before declaring it lost.
  grace,

  /// No hand detected and the grace window has expired.
  lost,
}

/// Snapshot of [HandGestureRecognizer] state emitted each frame by
/// [GestureInputSource.debugInfo]. Useful for building debug overlays.
final class GestureDebugInfo {
  const GestureDebugInfo({
    required this.phase,
    required this.pinchDistance,
    required this.landmarks,
    this.secondHandLandmarks = const [],
    this.isTwoHandActive = false,
    this.workerLatencyMs = 0,
    this.roundTripMs = 0,
  });

  final GesturePhase phase;

  /// Raw Euclidean distance between thumb tip and index tip (normalised 0–1).
  final double pinchDistance;

  /// The 21 MediaPipe landmarks for the primary hand, normalised to [0, 1].
  /// Empty when no hand is detected.
  final List<HandLandmarkPoint> landmarks;

  /// The 21 MediaPipe landmarks for the second hand when in two-hand mode,
  /// normalised to [0, 1]. Empty when fewer than two hands are detected.
  final List<HandLandmarkPoint> secondHandLandmarks;

  /// True while a two-hand spread/pinch gesture is active.
  final bool isTwoHandActive;

  /// Time the web worker spent on inference for this frame (ms), 0 on native.
  final double workerLatencyMs;

  /// Wall-clock round-trip time from sending the frame to receiving results (ms).
  final int roundTripMs;
}
