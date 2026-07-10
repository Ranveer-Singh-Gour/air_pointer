import 'package:air_pointer/air_pointer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists calibration and user-tunable settings across app restarts.
/// Backed by `shared_preferences` (NSUserDefaults on macOS) — a handful of
/// scalar values, not worth a file/JSON layer.
class AppSettingsStore {
  static const _kPinchClose = 'calibration.pinchCloseThreshold';
  static const _kPinchOpen = 'calibration.pinchOpenThreshold';
  static const _kMinCutoff = 'filter.minCutoff';
  static const _kBeta = 'filter.beta';
  static const _kLaunchAtLogin = 'settings.launchAtLogin';
  static const _kClickSoundEnabled = 'settings.clickSoundEnabled';
  static const _kSwipeGesturesEnabled = 'settings.swipeGesturesEnabled';
  static const _kTwoHandZoomEnabled = 'settings.twoHandZoomEnabled';
  static const _kPanicHotkeyEnabled = 'settings.panicHotkeyEnabled';
  static const _kGestureActionPrefix = 'gestureAction.';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<CalibrationResult?> loadCalibration() async {
    final prefs = await _prefs;
    final close = prefs.getDouble(_kPinchClose);
    final open = prefs.getDouble(_kPinchOpen);
    if (close == null || open == null) return null;
    if (open <= close) return null; // guards CalibrationResult's assert
    return CalibrationResult(pinchCloseThreshold: close, pinchOpenThreshold: open);
  }

  Future<void> saveCalibration(CalibrationResult result) async {
    final prefs = await _prefs;
    await prefs.setDouble(_kPinchClose, result.pinchCloseThreshold);
    await prefs.setDouble(_kPinchOpen, result.pinchOpenThreshold);
  }

  Future<({double minCutoff, double beta})?> loadFilterParams() async {
    final prefs = await _prefs;
    final minCutoff = prefs.getDouble(_kMinCutoff);
    final beta = prefs.getDouble(_kBeta);
    if (minCutoff == null || beta == null) return null;
    return (minCutoff: minCutoff, beta: beta);
  }

  Future<void> saveFilterParams({required double minCutoff, required double beta}) async {
    final prefs = await _prefs;
    await prefs.setDouble(_kMinCutoff, minCutoff);
    await prefs.setDouble(_kBeta, beta);
  }

  Future<bool> loadLaunchAtLogin() async => (await _prefs).getBool(_kLaunchAtLogin) ?? false;

  Future<void> saveLaunchAtLogin(bool enabled) async {
    await (await _prefs).setBool(_kLaunchAtLogin, enabled);
  }

  Future<bool> loadClickSoundEnabled() async => (await _prefs).getBool(_kClickSoundEnabled) ?? true;

  Future<void> saveClickSoundEnabled(bool enabled) async {
    await (await _prefs).setBool(_kClickSoundEnabled, enabled);
  }

  Future<bool> loadSwipeGesturesEnabled() async => (await _prefs).getBool(_kSwipeGesturesEnabled) ?? false;

  Future<void> saveSwipeGesturesEnabled(bool enabled) async {
    await (await _prefs).setBool(_kSwipeGesturesEnabled, enabled);
  }

  Future<bool> loadTwoHandZoomEnabled() async => (await _prefs).getBool(_kTwoHandZoomEnabled) ?? false;

  Future<void> saveTwoHandZoomEnabled(bool enabled) async {
    await (await _prefs).setBool(_kTwoHandZoomEnabled, enabled);
  }

  Future<bool> loadPanicHotkeyEnabled() async => (await _prefs).getBool(_kPanicHotkeyEnabled) ?? true;

  Future<void> savePanicHotkeyEnabled(bool enabled) async {
    await (await _prefs).setBool(_kPanicHotkeyEnabled, enabled);
  }

  /// Maps a [RecognizedGesture] (by enum name) to a user-chosen action id,
  /// e.g. `'missionControl'` — see `GestureActionExecutor`. Absent entries
  /// mean "no action bound."
  Future<String?> loadGestureAction(RecognizedGesture gesture) async =>
      (await _prefs).getString('$_kGestureActionPrefix${gesture.name}');

  Future<void> saveGestureAction(RecognizedGesture gesture, String? actionId) async {
    final prefs = await _prefs;
    final key = '$_kGestureActionPrefix${gesture.name}';
    if (actionId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, actionId);
    }
  }
}
