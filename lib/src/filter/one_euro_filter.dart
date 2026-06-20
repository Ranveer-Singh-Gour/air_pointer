import 'dart:math' as math;

/// Adaptive low-pass filter for noisy continuous 1D signals.
///
/// Reference: Casiez et al., "1€ Filter: A Simple Speed-based Low-pass Filter
/// for Noisy Input in Interactive Systems" (CHI 2012).
final class OneEuroFilter {
  OneEuroFilter({
    required this.minCutoff,
    required this.beta,
    this.dCutoff = 1.0,
  });

  final double minCutoff;
  final double beta;
  final double dCutoff;

  _LowPassFilter? _xFilter;
  _LowPassFilter? _dxFilter;
  double? _prevValue;
  double _lastVelocity = 0.0;

  /// Smoothed velocity estimate from the last [filter] call, in input-units/s.
  ///
  /// This is the derivative the filter already computes internally to adapt its
  /// cutoff frequency. Zero before the first call and after [reset].
  double get velocity => _lastVelocity;

  double filter(double value, double dt) {
    final dx = _prevValue == null ? 0.0 : (value - _prevValue!) / dt;
    _prevValue = value;
    final alphaDx = _alpha(dCutoff, dt);
    _dxFilter ??= _LowPassFilter(initialValue: dx);
    final dxFiltered = _dxFilter!.filter(dx, alphaDx);
    _lastVelocity = dxFiltered;
    final cutoff = minCutoff + beta * dxFiltered.abs();
    final alpha = _alpha(cutoff, dt);
    _xFilter ??= _LowPassFilter(initialValue: value);
    return _xFilter!.filter(value, alpha);
  }

  /// Clears internal state so the next [filter] call starts fresh.
  ///
  /// Call this when the input signal has had a discontinuity (e.g. hand
  /// tracking lost and reacquired) to prevent cursor warp on re-acquisition.
  void reset() {
    _xFilter = null;
    _dxFilter = null;
    _prevValue = null;
    _lastVelocity = 0.0;
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }
}

final class _LowPassFilter {
  _LowPassFilter({required double initialValue}) : _prev = initialValue;

  double _prev;

  double filter(double x, double alpha) =>
      _prev = alpha * x + (1 - alpha) * _prev;
}
