import 'package:air_pointer/src/gesture/calibration_result.dart';

/// Accumulates raw pinch-distance samples from [GestureDebugInfo] and
/// derives calibrated [CalibrationResult] thresholds for a specific user.
///
/// Usage:
/// 1. Call [addOpenSample] each frame while the user holds their hand open.
/// 2. When [openDone] is true, prompt the user to pinch.
/// 3. Call [addCloseSample] each frame while the user holds the pinch.
/// 4. When [closeDone] is true, call [compute] to get the result.
/// 5. Pass the result to [GestureInputSource.applyCalibration].
///
/// Only samples that meet the pose-confidence thresholds ([openMinDist] /
/// [closeMaxDist]) are counted, so the user can hold the pose loosely without
/// contaminating the calibration.
final class GestureCalibrator {
  /// Frames of qualifying samples required per pose (~2 s at 30 fps).
  static const int samplesNeeded = 60;

  /// Minimum thumb–index distance accepted as a clearly-open hand.
  static const double openMinDist = 0.10;

  /// Maximum thumb–index distance accepted as a clearly-closed pinch.
  static const double closeMaxDist = 0.07;

  final List<double> _openSamples = [];
  final List<double> _closeSamples = [];

  /// True when enough open-hand samples have been collected.
  bool get openDone => _openSamples.length >= samplesNeeded;

  /// True when enough pinch samples have been collected.
  bool get closeDone => _closeSamples.length >= samplesNeeded;

  /// Fraction of required open samples collected, in [0, 1].
  double get openProgress =>
      (_openSamples.length / samplesNeeded).clamp(0.0, 1.0);

  /// Fraction of required pinch samples collected, in [0, 1].
  double get closeProgress =>
      (_closeSamples.length / samplesNeeded).clamp(0.0, 1.0);

  /// Record one frame of open-hand distance. Only stored when the distance
  /// is above [openMinDist], confirming the hand is clearly open.
  void addOpenSample(double dist) {
    if (!openDone && dist > openMinDist) _openSamples.add(dist);
  }

  /// Record one frame of pinch distance. Only stored when the distance
  /// is below [closeMaxDist], confirming the hand is clearly pinching.
  void addCloseSample(double dist) {
    if (!closeDone && dist < closeMaxDist) _closeSamples.add(dist);
  }

  /// Compute calibrated thresholds from the collected samples.
  ///
  /// Returns null when:
  /// - Fewer than [samplesNeeded] samples exist for either pose, or
  /// - The open/close averages are too close together to be reliable.
  CalibrationResult? compute() {
    if (!openDone || !closeDone) return null;

    final openAvg = _openSamples.reduce((a, b) => a + b) / _openSamples.length;
    final closeAvg =
        _closeSamples.reduce((a, b) => a + b) / _closeSamples.length;

    // Require at least 4 % separation — any less and we can't reliably
    // distinguish the poses.
    if (openAvg - closeAvg < 0.04) return null;

    final range = openAvg - closeAvg;
    // Place the close threshold 25 % of the way from the pinch pose toward
    // open; place the open threshold at 55 % — this leaves a 30 % hysteresis
    // gap that prevents chatter.
    final close = (closeAvg + range * 0.25).clamp(0.02, 0.12);
    final open = (closeAvg + range * 0.55).clamp(close + 0.02, 0.20);

    return CalibrationResult(
      pinchCloseThreshold: close,
      pinchOpenThreshold: open,
    );
  }

  /// Clears all accumulated samples so calibration can restart.
  void reset() {
    _openSamples.clear();
    _closeSamples.clear();
  }
}
