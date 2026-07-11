import '../native/system_cursor_ffi.dart';

/// A system-level action a discrete hand gesture can trigger.
///
/// macOS has no public API for posting synthetic trackpad gestures (pinch,
/// swipe), so these are all implemented as their equivalent built-in
/// keyboard shortcuts instead — see [GestureActionExecutor.run].
enum GestureAction {
  missionControl,
  appExpose,
  spaceLeft,
  spaceRight;

  String get label => switch (this) {
        GestureAction.missionControl => 'Mission Control',
        GestureAction.appExpose => 'App Exposé',
        GestureAction.spaceLeft => 'Previous Space',
        GestureAction.spaceRight => 'Next Space',
      };
}

/// Runs a [GestureAction] by posting the matching macOS keyboard shortcut
/// via [SystemCursorFfi]. Stateless — safe to share one instance.
class GestureActionExecutor {
  GestureActionExecutor([SystemCursorFfi? ffi]) : _ffi = ffi ?? SystemCursorFfi.instance;

  final SystemCursorFfi _ffi;

  void run(GestureAction action) {
    switch (action) {
      case GestureAction.missionControl:
        _ffi.postKeyPress(SystemCursorFfi.kVkUpArrow, controlModifier: true);
      case GestureAction.appExpose:
        _ffi.postKeyPress(SystemCursorFfi.kVkDownArrow, controlModifier: true);
      case GestureAction.spaceLeft:
        _ffi.postKeyPress(SystemCursorFfi.kVkLeftArrow, controlModifier: true);
      case GestureAction.spaceRight:
        _ffi.postKeyPress(SystemCursorFfi.kVkRightArrow, controlModifier: true);
    }
  }
}
