import 'dart:async';
import 'dart:io';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app_status_screen.dart';
import 'src/calibration/calibration_screen.dart';
import 'src/cursor/gesture_action_executor.dart';
import 'src/cursor/gesture_session_controller.dart';
import 'src/debug/debug_tools_screen.dart';
import 'src/native/camera_permission.dart';
import 'src/native/cursor_backend.dart';
import 'src/native/launch_at_login.dart';
import 'src/native/panic_hotkey.dart';
import 'src/onboarding/onboarding_screen.dart';
import 'src/settings/settings_screen.dart';
import 'src/storage/app_settings_store.dart';
import 'src/tray/tray_controller.dart';

Future<void> main() async {
  // Uncaught errors in event-handler callbacks (button taps, etc.) are
  // otherwise easy to lose — Flutter's default zone reports them to stderr,
  // but under `flutter run` that can scroll past unnoticed, and a thrown
  // error partway through a callback (e.g. `setState` never reached)
  // otherwise looks indistinguishable from a UI that's just silently
  // hanging. Print loudly and clearly instead.
  runZonedGuarded(_run, (error, stack) {
    debugPrint('[air_pointer_app] UNCAUGHT: $error\n$stack');
  });
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await LaunchAtLogin.setUp();

  const windowOptions = WindowOptions(
    size: Size(360, 440),
    center: true,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  unawaited(windowManager.waitUntilReadyToShow(windowOptions, () async {
    // No window flash on launch in the shipped app — it's menu-bar-only
    // until opened from the tray. Under `flutter run` (kDebugMode), show
    // and activate it instead: hiding it immediately there reads as "the
    // app just crashed" rather than "it's running in the background,"
    // since there's no other on-screen signal that launch succeeded.
    //
    // `show()` (not just leaving the window as `waitUntilReadyToShow`
    // constructed it) matters specifically because it's the call that
    // triggers `NSApp.activate(ignoringOtherApps: true)` on the native
    // side — an accessory-policy app (no Dock icon) never becomes the
    // frontmost/key app on its own just because a window exists. Without
    // this, the window is technically visible but never focused, so
    // clicks and the system permission dialogs that follow can land on
    // the wrong app.
    if (kDebugMode) {
      await windowManager.show();
    } else {
      await windowManager.hide();
    }
  }));

  runApp(const AirPointerApp());
}

class AirPointerApp extends StatefulWidget {
  const AirPointerApp({super.key});

  @override
  State<AirPointerApp> createState() => _AirPointerAppState();
}

class _AirPointerAppState extends State<AirPointerApp> with WindowListener {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _settingsStore = AppSettingsStore();
  TrayController? _tray;
  GestureSessionController? _controller;
  StreamSubscription<HandTrackingStatus>? _statusSub;
  CalibrationResult? _lastCalibration;
  double _minCutoff = 1.0;
  double _beta = 0.05;
  bool _clickSoundEnabled = true;
  bool _swipeGesturesEnabled = false;
  bool _twoHandZoomEnabled = false;
  Map<RecognizedGesture, GestureAction> _gestureActions = {};

  /// Cached camera-authorization status (`'authorized'`, `'denied'`,
  /// `'restricted'`, `'notDetermined'`) — [CameraPermission.status] is
  /// async, but `build()` needs a synchronous read, so this is refreshed
  /// after every permission-flow step rather than checked inline.
  String _cameraStatus = 'notDetermined';
  bool _showOnboarding = false;

  bool get _enabled => _controller != null;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _tray = TrayController(
      onToggleEnabled: _handleToggleEnabled,
      onCalibrate: _handleCalibrate,
      onDebugTools: _handleDebugTools,
      onSettings: _handleSettings,
      onQuit: () => exit(0),
    )..init();
    unawaited(_refreshCameraStatus());
    unawaited(_loadPersistedSettings());
  }

  Future<void> _loadPersistedSettings() async {
    final store = _settingsStore;
    final calibration = await store.loadCalibration();
    final filterParams = await store.loadFilterParams();
    final clickSound = await store.loadClickSoundEnabled();
    final swipe = await store.loadSwipeGesturesEnabled();
    final zoom = await store.loadTwoHandZoomEnabled();
    final panic = await store.loadPanicHotkeyEnabled();
    final actions = <RecognizedGesture, GestureAction>{};
    for (final gesture in RecognizedGesture.values) {
      if (gesture == RecognizedGesture.none) continue;
      final action = await store.loadGestureAction(gesture);
      if (action != null) actions[gesture] = action;
    }
    if (!mounted) return;
    setState(() {
      _lastCalibration = calibration;
      if (filterParams != null) {
        _minCutoff = filterParams.minCutoff;
        _beta = filterParams.beta;
      }
      _clickSoundEnabled = clickSound;
      _swipeGesturesEnabled = swipe;
      _twoHandZoomEnabled = zoom;
      _gestureActions = actions;
    });
    if (panic) await PanicHotkey.register(_handlePanic);
  }

  Future<void> _refreshCameraStatus() async {
    final status = await CameraPermission.status();
    if (mounted) setState(() => _cameraStatus = status);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(PanicHotkey.unregister());
    unawaited(_statusSub?.cancel());
    _tray?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // Window "closing" hides rather than actually closes, so the
  // accessory-mode app keeps running in the tray.
  @override
  void onWindowClose() {
    windowManager.hide();
  }

  bool get _permissionsReady =>
      _cameraStatus == 'authorized' && CursorBackend.instance.isTrusted;

  /// Fully stops tracking (camera off) — the same effect as toggling
  /// "Cursor control: Off" from the tray, so the app status screen, tray
  /// icon, and `_enabled` state all stay consistent regardless of which
  /// path triggered it. Used by both [_handleToggleEnabled] and the panic
  /// hotkey: a partial "cursor control off but camera still on" state would
  /// be a weaker trust signal than the camera light actually going out, and
  /// would leave the UI showing "on" while nothing was actually happening.
  Future<void> _disable() async {
    unawaited(_statusSub?.cancel());
    _controller?.dispose();
    setState(() => _controller = null);
    await _tray?.setEnabled(false);
  }

  void _handlePanic() {
    if (!_enabled) return;
    unawaited(_disable());
  }

  Future<void> _handleToggleEnabled() async {
    if (_enabled) {
      await _disable();
      return;
    }

    await _refreshCameraStatus();
    if (!_permissionsReady) {
      setState(() => _showOnboarding = true);
      await windowManager.show();
      return;
    }
    setState(() => _showOnboarding = false);
    await _enableTracking(cursorControl: true);
  }

  Future<void> _enableTracking({required bool cursorControl}) async {
    final controller = GestureSessionController(
      onError: (e, st) => debugPrint('[air_pointer_app] $e\n$st'),
      swipeGesturesEnabled: _swipeGesturesEnabled,
      twoHandZoomEnabled: _twoHandZoomEnabled,
      clickSoundEnabled: _clickSoundEnabled,
      gestureActions: _gestureActions,
    );
    await controller.start();
    controller.source.setFilterParams(minCutoff: _minCutoff, beta: _beta);
    final calibration = _lastCalibration;
    if (calibration != null) controller.source.applyCalibration(calibration);
    controller.setCursorControlEnabled(cursorControl);
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    await _tray?.setEnabled(cursorControl);
    unawaited(_statusSub?.cancel());
    _statusSub = controller.source.statusStream.listen((status) => _tray?.setStatus(status));
  }

  Future<void> _handleCalibrate() async {
    await _refreshCameraStatus();
    if (!_permissionsReady) {
      setState(() => _showOnboarding = true);
      await windowManager.show();
      return;
    }
    setState(() => _showOnboarding = false);

    var controller = _controller;
    final startedTemporarily = controller == null;
    if (controller == null) {
      // Not enabled — spin up a tracking-only session (camera on, cursor
      // control off) just long enough to calibrate, then tear it down
      // again, so "Calibrate" doesn't silently flip "Enabled" on.
      controller = GestureSessionController(
        onError: (e, st) => debugPrint('[air_pointer_app] $e\n$st'),
        swipeGesturesEnabled: _swipeGesturesEnabled,
        twoHandZoomEnabled: _twoHandZoomEnabled,
        clickSoundEnabled: _clickSoundEnabled,
        gestureActions: _gestureActions,
      );
      await controller.start();
      controller.source.setFilterParams(minCutoff: _minCutoff, beta: _beta);
      final calibration = _lastCalibration;
      if (calibration != null) controller.source.applyCalibration(calibration);
    }

    await windowManager.show();
    final navState = _navigatorKey.currentState;
    if (navState != null && navState.mounted) {
      final result = await showDialog<CalibrationResult?>(
        context: navState.context,
        barrierDismissible: false,
        builder: (_) => CalibrationDialog(
          source: controller!.source,
          initialMinCutoff: _minCutoff,
          initialBeta: _beta,
          onFilterParamsChanged: (minCutoff, beta) {
            _minCutoff = minCutoff;
            _beta = beta;
            unawaited(_settingsStore.saveFilterParams(minCutoff: minCutoff, beta: beta));
          },
        ),
      );
      if (result != null) {
        _lastCalibration = result;
        unawaited(_settingsStore.saveCalibration(result));
      }
    }

    if (startedTemporarily) controller.dispose();
    await windowManager.hide();
  }

  void _handleDebugTools() {
    if (_enabled) {
      // Both the main session and a debug-tools tab would try to attach to
      // the single native hand-landmark event stream — the native side
      // only tracks one active sink, so the second listener silently steals
      // frames from the first. Simplest safe rule for v0: don't allow both
      // at once.
      return;
    }
    windowManager.show();
    _navigatorKey.currentState?.pushNamed('/debug');
  }

  void _handleSettings() {
    windowManager.show();
    _navigatorKey.currentState?.pushNamed('/settings');
  }

  Future<void> _onOnboardingComplete() async {
    await _refreshCameraStatus();
    setState(() => _showOnboarding = false);
    await _enableTracking(cursorControl: true);
    // Deliberately NOT hiding here (unlike the launch-time hide in `main()`)
    // — right after granting two OS permissions, a first-time user needs to
    // see *something* confirming it worked. `_showOnboarding = false` above
    // already transitions `build()` to `AppStatusScreen` ("Cursor control
    // is on"); hiding the window immediately after made a successful setup
    // indistinguishable from a hang, since nothing else signals success.
    // The window can still be dismissed normally (its close button hides
    // it, same as any other window in this app — see `onWindowClose`).
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'air_pointer_app',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      routes: {
        '/debug': (_) => const DebugToolsScreen(),
        '/settings': (_) => SettingsScreen(
              store: _settingsStore,
              getActiveController: () => _controller,
              onPanic: _handlePanic,
            ),
      },
      home: _showOnboarding || !_permissionsReady
          ? OnboardingScreen(onComplete: _onOnboardingComplete)
          : AppStatusScreen(
              enabled: _enabled,
              onToggleEnabled: _handleToggleEnabled,
              onCalibrate: _handleCalibrate,
              onDebugTools: _handleDebugTools,
              onSettings: _handleSettings,
            ),
    );
  }
}
