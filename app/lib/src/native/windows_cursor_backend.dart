import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../cursor/system_shortcut.dart';
import 'cursor_backend.dart';

/// `SendInput`-based cursor/keyboard injection for Windows, via the `win32`
/// package's FFI bindings (already a transitive dependency through
/// `hotkey_manager_windows` — used directly here rather than hand-rolling
/// `INPUT`/`MOUSEINPUT`/`KEYBDINPUT` struct layouts, which have historically
/// tricky x64 padding/alignment that a maintained, widely-used binding gets
/// right).
///
/// UNTESTED: written and built for Windows in an environment with no
/// Windows machine to run it on. The struct layouts and flag values come
/// from a reviewed third-party binding and Microsoft's documented
/// `SendInput` contract, giving the same confidence level as
/// [MacosCursorBackend]'s hand-written CoreGraphics bindings, but neither
/// this class nor `app/windows/` has ever actually been built or launched.
class WindowsCursorBackend implements CursorBackend {
  // A normal-integrity-level process's SendInput calls need no special
  // permission on Windows (unlike macOS's Accessibility trust) — this can
  // only fail silently against an elevated (admin) target window, via UIPI,
  // which this app has no way to detect or work around.
  @override
  bool get isTrusted => true;

  @override
  Rect get combinedDisplayBounds {
    final left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    final top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    final width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    final height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    return Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }

  /// `SendInput`'s absolute-coordinate mode maps dx/dy through a 0-65535
  /// normalized range, not real pixels — `MOUSEEVENTF_VIRTUALDESK` makes
  /// that range span every monitor ([combinedDisplayBounds]) instead of
  /// just the primary one.
  int _normalize(double value, double origin, double extent) {
    if (extent <= 0) return 0;
    return (((value - origin) * 65536) / extent).round().clamp(0, 65535);
  }

  void _sendMouse(int flags, {Offset? position, int mouseData = 0}) {
    var moveFlags = flags;
    var dx = 0, dy = 0;
    if (position != null) {
      final bounds = combinedDisplayBounds;
      dx = _normalize(position.dx, bounds.left, bounds.width);
      dy = _normalize(position.dy, bounds.top, bounds.height);
      moveFlags |= MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
    }
    final input = calloc<INPUT>();
    try {
      input.ref.type = INPUT_MOUSE;
      input.ref.mi.dx = dx;
      input.ref.mi.dy = dy;
      input.ref.mi.mouseData = mouseData;
      input.ref.mi.dwFlags = moveFlags;
      SendInput(1, input, sizeOf<INPUT>());
    } finally {
      calloc.free(input);
    }
  }

  @override
  void moveTo(Offset position) => _sendMouse(0, position: position);

  @override
  void mouseDown(Offset position) => _sendMouse(MOUSEEVENTF_LEFTDOWN, position: position);

  @override
  void mouseDragged(Offset position) => _sendMouse(0, position: position);

  @override
  void mouseUp(Offset position) => _sendMouse(MOUSEEVENTF_LEFTUP, position: position);

  /// `WHEEL_DELTA` (120) is Windows' "one notch" scroll unit — not exposed
  /// as a named constant by `package:win32`, so it's inlined here per
  /// Microsoft's documented value (`WinUser.h`).
  static const _wheelDelta = 120;

  @override
  void scroll(double deltaY, {bool zoomModifier = false}) {
    if (zoomModifier) _sendKey(VK_CONTROL, down: true);
    _sendMouse(MOUSEEVENTF_WHEEL, mouseData: (deltaY.sign * _wheelDelta).round());
    if (zoomModifier) _sendKey(VK_CONTROL, down: false);
  }

  void _sendKey(int virtualKey, {required bool down}) {
    final input = calloc<INPUT>();
    try {
      input.ref.type = INPUT_KEYBOARD;
      input.ref.ki.wVk = virtualKey;
      input.ref.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
      SendInput(1, input, sizeOf<INPUT>());
    } finally {
      calloc.free(input);
    }
  }

  void _pressCombo(List<int> virtualKeys) {
    for (final key in virtualKeys) {
      _sendKey(key, down: true);
    }
    for (final key in virtualKeys.reversed) {
      _sendKey(key, down: false);
    }
  }

  @override
  void triggerShortcut(SystemShortcut shortcut) {
    switch (shortcut) {
      case SystemShortcut.missionControl:
        _pressCombo([VK_LWIN, VK_TAB]); // Task View — closest Windows analog
      case SystemShortcut.appExpose:
        _pressCombo([VK_LWIN, 0x44]); // Win+D (0x44 = 'D') — Show desktop
      case SystemShortcut.spaceLeft:
        _pressCombo([VK_CONTROL, VK_LWIN, VK_LEFT]); // previous virtual desktop
      case SystemShortcut.spaceRight:
        _pressCombo([VK_CONTROL, VK_LWIN, VK_RIGHT]); // next virtual desktop
    }
  }

  /// Runs [path] via the shell's `start`, which resolves `.lnk` shortcuts
  /// and file associations the way double-clicking would — the closest
  /// Windows analog to macOS's `open -a`. The empty `""` argument is
  /// required by `start`'s own argument parsing (it treats the first
  /// quoted string as a window title, not the target).
  @override
  void openApp(String path) {
    unawaited(Process.run('cmd', ['/c', 'start', '""', path]));
  }
}
