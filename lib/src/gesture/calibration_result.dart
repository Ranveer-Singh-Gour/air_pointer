/// Per-user detection thresholds for [GestureInputSource].
///
/// Default thresholds work well for most hands in good lighting. Run
/// [GestureCalibrator] to derive thresholds tuned to a specific user's hand
/// size and environment, then apply them with
/// [GestureInputSource.applyCalibration].
final class CalibrationResult {
  const CalibrationResult({
    required this.pinchCloseThreshold,
    required this.pinchOpenThreshold,
  }) : assert(
          pinchOpenThreshold > pinchCloseThreshold,
          'openThreshold must be greater than closeThreshold',
        );

  /// Normalised thumb–index distance below which a pinch gesture begins.
  final double pinchCloseThreshold;

  /// Normalised thumb–index distance above which a pinch gesture ends.
  final double pinchOpenThreshold;

  /// Factory defaults applied when no calibration has been run.
  static const defaults = CalibrationResult(
    pinchCloseThreshold: 0.05,
    pinchOpenThreshold: 0.08,
  );
}
