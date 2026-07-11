import 'package:flutter/services.dart';

/// Thin wrapper over the native `air_pointer_app/permissions` channel for
/// the one-off camera-authorization calls. Accessibility trust is handled
/// separately, via FFI (`system_cursor_ffi.dart`, Stage 3), not this channel.
class CameraPermission {
  static const _channel = MethodChannel('air_pointer_app/permissions');

  /// `'authorized'`, `'denied'`, `'restricted'`, or `'notDetermined'`.
  static Future<String> status() async =>
      (await _channel.invokeMethod<String>('cameraAuthorizationStatus')) ?? 'notDetermined';

  /// Shows the OS camera-permission prompt if not yet determined. Returns
  /// whether access is granted. No-ops (and returns the current status) if
  /// already authorized or already denied — macOS won't re-prompt after a
  /// denial; the caller should direct the user to System Settings instead.
  static Future<bool> request() async =>
      (await _channel.invokeMethod<bool>('requestCameraAccess')) ?? false;
}
