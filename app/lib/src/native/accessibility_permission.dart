import 'package:flutter/services.dart';

/// Deep-links to System Settings' Accessibility pane (macOS only — Windows'
/// `CursorBackend.isTrusted` is always `true`, so this is never invoked
/// there). Trust *status* itself is checked via `CursorBackend.isTrusted`
/// (dart:ffi -> `AXIsProcessTrusted` on macOS), not this channel — this only
/// owns the AppKit-only "open System Settings" call, same channel as
/// [CameraPermission].
class AccessibilityPermission {
  static const _channel = MethodChannel('air_pointer_app/permissions');

  static Future<void> openSystemSettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');
}
