import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// Global "kill switch" hotkey — fires even when this app isn't focused, so
/// cursor control can be shut off without having to find the tray icon
/// while the hand-tracked cursor is misbehaving.
///
/// Control+Shift+Escape: doesn't collide with any macOS system shortcut
/// (Force Quit is Cmd+Option+Esc).
class PanicHotkey {
  static final _hotKey = HotKey(
    key: PhysicalKeyboardKey.escape,
    modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    scope: HotKeyScope.system,
  );

  static const label = 'Control + Shift + Escape';

  static bool _registered = false;

  static Future<void> register(void Function() onPanic) async {
    if (_registered) return;
    await hotKeyManager.register(_hotKey, keyDownHandler: (_) => onPanic());
    _registered = true;
  }

  static Future<void> unregister() async {
    if (!_registered) return;
    await hotKeyManager.unregister(_hotKey);
    _registered = false;
  }
}
