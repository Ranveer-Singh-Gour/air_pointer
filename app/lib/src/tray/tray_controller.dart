import 'package:air_pointer/air_pointer.dart';
import 'package:tray_manager/tray_manager.dart';

/// Wraps `tray_manager`: the status-item icon + dropdown menu. Menu actions
/// are reported via [onToggleEnabled]/[onCalibrate]/[onDebugTools]/[onQuit]
/// callbacks — this class owns no app state itself, just the native tray
/// widget and its icon.
class TrayController with TrayListener {
  TrayController({
    required this.onToggleEnabled,
    required this.onCalibrate,
    required this.onDebugTools,
    required this.onSettings,
    required this.onQuit,
  });

  final void Function() onToggleEnabled;
  final void Function() onCalibrate;
  final void Function() onDebugTools;
  final void Function() onSettings;
  final void Function() onQuit;

  bool _enabled = false;

  static const _idleIcon = 'assets/tray/idle_template.png';
  static const _activeIcon = 'assets/tray/active_template.png';
  static const _initializingIcon = 'assets/tray/initializing_template.png';
  static const _lostIcon = 'assets/tray/lost_template.png';
  static const _errorIcon = 'assets/tray/error_template.png';

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon(_idleIcon);
    await _rebuildMenu();
  }

  /// Reflects the current enabled state in the icon and the menu's checkbox.
  /// Call after every enable/disable transition. A subsequent [setStatus]
  /// call refines the icon further while enabled.
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await trayManager.setIcon(enabled ? _activeIcon : _idleIcon);
    await _rebuildMenu();
  }

  /// Reflects live [HandTrackingStatus] transitions in the tray icon while
  /// enabled — initializing/tracking/lost/error each get a distinct glyph
  /// instead of collapsing everything into one "on" icon. Ignored while
  /// disabled (icon stays idle regardless of a stale status).
  Future<void> setStatus(HandTrackingStatus status) async {
    if (!_enabled) return;
    final icon = switch (status) {
      HandTrackingInitializing() || HandTrackingCameraReady() => _initializingIcon,
      HandTrackingTracking() => _activeIcon,
      HandTrackingLost() => _lostIcon,
      HandTrackingError() => _errorIcon,
    };
    await trayManager.setIcon(icon);
  }

  Future<void> _rebuildMenu() => trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem.checkbox(
              key: 'toggle_enabled',
              label: _enabled ? 'Cursor control: On' : 'Cursor control: Off',
              checked: _enabled,
            ),
            MenuItem.separator(),
            MenuItem(key: 'calibrate', label: 'Calibrate…'),
            MenuItem(key: 'settings', label: 'Settings…'),
            MenuItem(key: 'debug_tools', label: 'Debug tools…'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit'),
          ],
        ),
      );

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'toggle_enabled':
        onToggleEnabled();
      case 'calibrate':
        onCalibrate();
      case 'settings':
        onSettings();
      case 'debug_tools':
        onDebugTools();
      case 'quit':
        onQuit();
    }
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}
