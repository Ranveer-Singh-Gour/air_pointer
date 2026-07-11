/// An OS-level shortcut used to approximate a trackpad/gesture interaction
/// neither macOS nor Windows expose a public API to post synthetically
/// (Mission Control, Spaces / virtual desktops, App Exposé / Task View).
///
/// Each [CursorBackend] implementation maps these to its own platform's
/// actual key combination — see `MacosCursorBackend.triggerShortcut` and
/// `WindowsCursorBackend.triggerShortcut`.
enum SystemShortcut {
  missionControl,
  appExpose,
  spaceLeft,
  spaceRight;

  String get label => switch (this) {
        SystemShortcut.missionControl => 'Mission Control',
        SystemShortcut.appExpose => 'App Exposé',
        SystemShortcut.spaceLeft => 'Previous Space',
        SystemShortcut.spaceRight => 'Next Space',
      };
}
