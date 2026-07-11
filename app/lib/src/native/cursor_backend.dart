import 'dart:io';
import 'dart:ui';

import '../cursor/system_shortcut.dart';
import 'macos_cursor_backend.dart';
import 'windows_cursor_backend.dart';

/// Platform-specific real-cursor injection — move/click/drag/scroll, plus
/// keyboard-shortcut and app-launch execution for [GestureActionExecutor].
/// `SystemCursorSink`/`GestureActionExecutor` code against this interface
/// only; the two implementations own everything OS-specific (which FFI
/// library, which trust model, which virtual-key codes).
abstract interface class CursorBackend {
  /// Picks the implementation for the current OS. Called once and cached —
  /// see [instance].
  factory CursorBackend.forPlatform() {
    if (Platform.isMacOS) return MacosCursorBackend();
    if (Platform.isWindows) return WindowsCursorBackend();
    throw UnsupportedError(
      'CursorBackend has no implementation for ${Platform.operatingSystem} — '
      'air_pointer_app currently ships macOS and Windows-scaffold support only.',
    );
  }

  static final CursorBackend instance = CursorBackend.forPlatform();

  /// Whether this process is currently allowed to inject synthetic
  /// input system-wide. macOS gates this behind the Accessibility
  /// permission (`AXIsProcessTrusted`) and can be `false`; Windows'
  /// `SendInput` needs no such grant from a normal user-mode process, so
  /// the Windows implementation always returns `true`.
  bool get isTrusted;

  /// Union of every active display's bounds, in the same global coordinate
  /// space [moveTo] etc. expect. A monitor positioned left of or above the
  /// primary one has a negative origin in this space on both platforms.
  Rect get combinedDisplayBounds;

  void moveTo(Offset position);
  void mouseDown(Offset position);
  void mouseDragged(Offset position);
  void mouseUp(Offset position);

  /// Posts a vertical scroll. Positive [deltaY] scrolls up. [zoomModifier]
  /// holds the platform's pinch-to-zoom proxy modifier while scrolling
  /// (Cmd on macOS, Ctrl on Windows) — many apps treat modifier+scroll as a
  /// zoom step.
  void scroll(double deltaY, {bool zoomModifier = false});

  /// Posts whichever key combination this platform uses for [shortcut].
  void triggerShortcut(SystemShortcut shortcut);

  /// Launches an app. macOS takes a `.app` bundle path (uses `open -a`);
  /// Windows takes an executable or shortcut path (launched directly).
  void openApp(String path);
}
