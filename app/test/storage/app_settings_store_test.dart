import 'package:air_pointer/air_pointer.dart';
import 'package:air_pointer_app/src/cursor/gesture_action_executor.dart';
import 'package:air_pointer_app/src/cursor/system_shortcut.dart';
import 'package:air_pointer_app/src/storage/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppSettingsStore calibration', () {
    test('loadCalibration returns null when nothing has been saved', () async {
      final store = AppSettingsStore();
      expect(await store.loadCalibration(), isNull);
    });

    test('saveCalibration then loadCalibration round-trips', () async {
      final store = AppSettingsStore();
      const result = CalibrationResult(pinchCloseThreshold: 0.04, pinchOpenThreshold: 0.09);
      await store.saveCalibration(result);
      final loaded = await store.loadCalibration();
      expect(loaded, isNotNull);
      expect(loaded!.pinchCloseThreshold, 0.04);
      expect(loaded.pinchOpenThreshold, 0.09);
    });

    test('loadCalibration guards against a corrupt open<=close state', () async {
      // Simulates a partially-written or manually-edited prefs file where
      // the open/close invariant CalibrationResult's constructor normally
      // enforces has been violated — should degrade to "no calibration"
      // rather than throw when GestureSessionController applies it.
      SharedPreferences.setMockInitialValues({
        'calibration.pinchCloseThreshold': 0.08,
        'calibration.pinchOpenThreshold': 0.05,
      });
      final store = AppSettingsStore();
      expect(await store.loadCalibration(), isNull);
    });
  });

  group('AppSettingsStore filter params', () {
    test('loadFilterParams returns null when nothing has been saved', () async {
      final store = AppSettingsStore();
      expect(await store.loadFilterParams(), isNull);
    });

    test('saveFilterParams then loadFilterParams round-trips', () async {
      final store = AppSettingsStore();
      await store.saveFilterParams(minCutoff: 2.5, beta: 0.12);
      final loaded = await store.loadFilterParams();
      expect(loaded, isNotNull);
      expect(loaded!.minCutoff, 2.5);
      expect(loaded.beta, 0.12);
    });
  });

  group('AppSettingsStore boolean toggles', () {
    test('launchAtLogin defaults to false and round-trips', () async {
      final store = AppSettingsStore();
      expect(await store.loadLaunchAtLogin(), isFalse);
      await store.saveLaunchAtLogin(true);
      expect(await store.loadLaunchAtLogin(), isTrue);
    });

    test('clickSoundEnabled defaults to true and round-trips', () async {
      final store = AppSettingsStore();
      expect(await store.loadClickSoundEnabled(), isTrue);
      await store.saveClickSoundEnabled(false);
      expect(await store.loadClickSoundEnabled(), isFalse);
    });

    test('swipeGesturesEnabled defaults to false and round-trips', () async {
      final store = AppSettingsStore();
      expect(await store.loadSwipeGesturesEnabled(), isFalse);
      await store.saveSwipeGesturesEnabled(true);
      expect(await store.loadSwipeGesturesEnabled(), isTrue);
    });

    test('twoHandZoomEnabled defaults to false and round-trips', () async {
      final store = AppSettingsStore();
      expect(await store.loadTwoHandZoomEnabled(), isFalse);
      await store.saveTwoHandZoomEnabled(true);
      expect(await store.loadTwoHandZoomEnabled(), isTrue);
    });

    test('panicHotkeyEnabled defaults to true and round-trips', () async {
      final store = AppSettingsStore();
      expect(await store.loadPanicHotkeyEnabled(), isTrue);
      await store.savePanicHotkeyEnabled(false);
      expect(await store.loadPanicHotkeyEnabled(), isFalse);
    });
  });

  group('AppSettingsStore gesture actions', () {
    test('loadGestureAction returns null when unbound', () async {
      final store = AppSettingsStore();
      expect(await store.loadGestureAction(RecognizedGesture.thumbUp), isNull);
    });

    test('saveGestureAction then loadGestureAction round-trips a shortcut', () async {
      final store = AppSettingsStore();
      await store.saveGestureAction(RecognizedGesture.thumbUp, const SystemShortcutAction(SystemShortcut.missionControl));
      final loaded = await store.loadGestureAction(RecognizedGesture.thumbUp);
      expect(loaded, isA<SystemShortcutAction>());
      expect((loaded! as SystemShortcutAction).shortcut, SystemShortcut.missionControl);
    });

    test('saveGestureAction then loadGestureAction round-trips an open-app action', () async {
      final store = AppSettingsStore();
      await store.saveGestureAction(RecognizedGesture.victory, const OpenAppAction('/Applications/Safari.app'));
      final loaded = await store.loadGestureAction(RecognizedGesture.victory);
      expect(loaded, isA<OpenAppAction>());
      expect((loaded! as OpenAppAction).appPath, '/Applications/Safari.app');
    });

    test('saveGestureAction with null clears the binding', () async {
      final store = AppSettingsStore();
      await store.saveGestureAction(RecognizedGesture.openPalm, const SystemShortcutAction(SystemShortcut.appExpose));
      await store.saveGestureAction(RecognizedGesture.openPalm, null);
      expect(await store.loadGestureAction(RecognizedGesture.openPalm), isNull);
    });

    test('bindings for different gestures do not collide', () async {
      final store = AppSettingsStore();
      await store.saveGestureAction(RecognizedGesture.thumbUp, const SystemShortcutAction(SystemShortcut.spaceLeft));
      await store.saveGestureAction(RecognizedGesture.thumbDown, const SystemShortcutAction(SystemShortcut.spaceRight));
      final up = await store.loadGestureAction(RecognizedGesture.thumbUp);
      final down = await store.loadGestureAction(RecognizedGesture.thumbDown);
      expect((up! as SystemShortcutAction).shortcut, SystemShortcut.spaceLeft);
      expect((down! as SystemShortcutAction).shortcut, SystemShortcut.spaceRight);
    });
  });
}
