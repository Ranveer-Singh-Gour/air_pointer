import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

/// Thin wrapper around `launch_at_startup` (macOS: `SMAppService`-backed
/// login item). Must call [setUp] once before [isEnabled]/[setEnabled].
class LaunchAtLogin {
  static bool _isSetUp = false;

  // Matches CFBundleName ($(PRODUCT_NAME), from the Xcode project) — not
  // read at runtime to avoid pulling in package_info_plus for one string.
  static const _appName = 'air_pointer_app';

  static Future<void> setUp() async {
    if (_isSetUp) return;
    launchAtStartup.setup(
      appName: _appName,
      appPath: Platform.resolvedExecutable,
    );
    _isSetUp = true;
  }

  static Future<bool> isEnabled() => launchAtStartup.isEnabled();

  static Future<void> setEnabled(bool enabled) =>
      enabled ? launchAtStartup.enable().then((_) {}) : launchAtStartup.disable().then((_) {});
}
