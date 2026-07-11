import 'dart:ffi';
import 'dart:ui';

import 'package:ffi/ffi.dart';

/// Direct `dart:ffi` bindings into CoreGraphics/ApplicationServices — no
/// Swift/MethodChannel round trip. These are plain C symbols in system
/// frameworks already loaded into every macOS process, reachable via
/// `DynamicLibrary.process()` with no linking step. Keeps the click/drag
/// state machine (`SystemCursorSink`) in Dart alongside the rest of this
/// package's logic, and avoids per-event channel overhead at 30-60Hz.
class SystemCursorFfi {
  SystemCursorFfi._() {
    final lib = DynamicLibrary.process();

    _cgEventCreateMouseEvent = lib.lookupFunction<_CGEventCreateMouseEventNative, _CGEventCreateMouseEventDart>(
      'CGEventCreateMouseEvent',
    );
    _cgEventCreateScrollWheelEvent =
        lib.lookupFunction<_CGEventCreateScrollWheelEventNative, _CGEventCreateScrollWheelEventDart>(
      'CGEventCreateScrollWheelEvent',
    );
    _cgEventPost = lib.lookupFunction<_CGEventPostNative, _CGEventPostDart>('CGEventPost');
    _cfRelease = lib.lookupFunction<_CFReleaseNative, _CFReleaseDart>('CFRelease');
    _axIsProcessTrusted = lib.lookupFunction<_AXIsProcessTrustedNative, _AXIsProcessTrustedDart>(
      'AXIsProcessTrusted',
    );
    _cgMainDisplayID = lib.lookupFunction<_CGMainDisplayIDNative, _CGMainDisplayIDDart>('CGMainDisplayID');
    _cgDisplayBounds = lib.lookupFunction<_CGDisplayBoundsNative, _CGDisplayBoundsDart>('CGDisplayBounds');
    _cgGetActiveDisplayList = lib.lookupFunction<_CGGetActiveDisplayListNative, _CGGetActiveDisplayListDart>(
      'CGGetActiveDisplayList',
    );
    _cgEventCreateKeyboardEvent =
        lib.lookupFunction<_CGEventCreateKeyboardEventNative, _CGEventCreateKeyboardEventDart>(
      'CGEventCreateKeyboardEvent',
    );
    _cgEventSetFlags = lib.lookupFunction<_CGEventSetFlagsNative, _CGEventSetFlagsDart>('CGEventSetFlags');
  }

  static final SystemCursorFfi instance = SystemCursorFfi._();

  late final _CGEventCreateMouseEventDart _cgEventCreateMouseEvent;
  late final _CGEventCreateScrollWheelEventDart _cgEventCreateScrollWheelEvent;
  late final _CGEventPostDart _cgEventPost;
  late final _CFReleaseDart _cfRelease;
  late final _AXIsProcessTrustedDart _axIsProcessTrusted;
  late final _CGMainDisplayIDDart _cgMainDisplayID;
  late final _CGDisplayBoundsDart _cgDisplayBounds;
  late final _CGGetActiveDisplayListDart _cgGetActiveDisplayList;
  late final _CGEventCreateKeyboardEventDart _cgEventCreateKeyboardEvent;
  late final _CGEventSetFlagsDart _cgEventSetFlags;

  // CGEventType (CGEventTypes.h)
  static const int _kCGEventMouseMoved = 5;
  static const int _kCGEventLeftMouseDown = 1;
  static const int _kCGEventLeftMouseUp = 2;
  static const int _kCGEventLeftMouseDragged = 6;

  // CGMouseButton
  static const int _kCGMouseButtonLeft = 0;

  // CGEventTapLocation
  static const int _kCGHIDEventTap = 0;

  // CGScrollEventUnit
  static const int _kCGScrollEventUnitPixel = 0;

  // CGEventFlags (CGEventTypes.h) — only the bits this app posts.
  static const int _kCGEventFlagMaskCommand = 0x00100000;
  static const int _kCGEventFlagMaskControl = 0x00040000;

  // Virtual keycodes (Carbon HIToolbox/Events.h) — arrows only, this app
  // never posts character keys.
  static const int kVkLeftArrow = 0x7B;
  static const int kVkRightArrow = 0x7C;
  static const int kVkDownArrow = 0x7D;
  static const int kVkUpArrow = 0x7E;

  /// Whether this process is trusted for Accessibility (required for
  /// [post]/[scroll] to have any effect — `CGEventPost` silently no-ops
  /// otherwise). No prompting side effect; direct the user to
  /// System Settings > Privacy & Security > Accessibility if this is false
  /// (see `PermissionsChannel.openAccessibilitySettings` on the Swift side).
  bool get isAccessibilityTrusted => _axIsProcessTrusted();

  /// Bounds of the main display, in the same coordinate space `CGEventPost`
  /// expects for mouse positions.
  Rect get mainDisplayBounds {
    final id = _cgMainDisplayID();
    final rect = _cgDisplayBounds(id);
    return Rect.fromLTWH(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
  }

  /// Union of every active display's bounds, in global desktop coordinates
  /// (the same space `CGEventPost` expects). A secondary monitor positioned
  /// left of or above the main one has a *negative* origin in this space —
  /// callers that use this as a `canvasSize` (which implicitly starts
  /// position values at `(0, 0)`) must add [combinedDisplayBounds]`.topLeft`
  /// back as an offset before posting positions to CGEvent calls, or cursor
  /// placement will be off by exactly that offset on any non-trivial
  /// monitor arrangement. Falls back to [mainDisplayBounds] if the display
  /// list can't be read.
  Rect get combinedDisplayBounds {
    const maxDisplays = 16;
    final ids = calloc<Uint32>(maxDisplays);
    final count = calloc<Uint32>();
    try {
      final err = _cgGetActiveDisplayList(maxDisplays, ids, count);
      if (err != 0 || count.value == 0) return mainDisplayBounds;
      Rect? union;
      for (var i = 0; i < count.value; i++) {
        final rect = _cgDisplayBounds(ids[i]);
        final bounds = Rect.fromLTWH(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
        union = union == null ? bounds : union.expandToInclude(bounds);
      }
      return union ?? mainDisplayBounds;
    } finally {
      calloc.free(ids);
      calloc.free(count);
    }
  }

  void _postMouseEvent(int type, Offset position, {int button = _kCGMouseButtonLeft}) {
    final point = Struct.create<_CGPoint>()
      ..x = position.dx
      ..y = position.dy;
    final event = _cgEventCreateMouseEvent(nullptr, type, point, button);
    if (event == nullptr) return;
    _cgEventPost(_kCGHIDEventTap, event);
    _cfRelease(event.cast());
  }

  /// Moves the cursor to [position] without any button pressed.
  void moveTo(Offset position) => _postMouseEvent(_kCGEventMouseMoved, position);

  /// Presses the left mouse button down at [position].
  void mouseDown(Offset position) => _postMouseEvent(_kCGEventLeftMouseDown, position);

  /// Moves the cursor to [position] while the left mouse button is held.
  void mouseDragged(Offset position) => _postMouseEvent(_kCGEventLeftMouseDragged, position);

  /// Releases the left mouse button at [position].
  void mouseUp(Offset position) => _postMouseEvent(_kCGEventLeftMouseUp, position);

  /// Posts a vertical scroll-wheel event. Positive [deltaY] scrolls up.
  ///
  /// `CGEventCreateScrollWheelEvent` is a C variadic function
  /// (`..., int32_t wheel1, ...`) — dart:ffi can't express true variadic
  /// calls, but declaring the exact fixed arity actually used here
  /// (`wheelCount = 1`, one `wheel1` argument) works because x86_64/arm64's
  /// calling convention passes the declared prefix and first variadic
  /// integer argument identically either way. This is a widely used pattern
  /// for calling this specific API from FFI, not a general variadic
  /// workaround.
  void scroll(double deltaY, {bool cmdModifier = false}) {
    final event = _cgEventCreateScrollWheelEvent(nullptr, _kCGScrollEventUnitPixel, 1, deltaY.round());
    if (event == nullptr) return;
    if (cmdModifier) _cgEventSetFlags(event, _kCGEventFlagMaskCommand);
    _cgEventPost(_kCGHIDEventTap, event);
    _cfRelease(event.cast());
  }

  /// Posts a key-down then key-up for [keyCode] (one of the `kVK_*`
  /// constants) with [controlModifier] optionally held — used to approximate
  /// gestures macOS has no public synthetic-event API for (space-switching,
  /// Mission Control) via their built-in keyboard shortcuts instead.
  void postKeyPress(int keyCode, {bool controlModifier = false}) {
    final flags = controlModifier ? _kCGEventFlagMaskControl : 0;
    final down = _cgEventCreateKeyboardEvent(nullptr, keyCode, true);
    if (down != nullptr) {
      if (flags != 0) _cgEventSetFlags(down, flags);
      _cgEventPost(_kCGHIDEventTap, down);
      _cfRelease(down.cast());
    }
    final up = _cgEventCreateKeyboardEvent(nullptr, keyCode, false);
    if (up != nullptr) {
      if (flags != 0) _cgEventSetFlags(up, flags);
      _cgEventPost(_kCGHIDEventTap, up);
      _cfRelease(up.cast());
    }
  }
}

// ── Struct layouts (CoreGraphics/CGGeometry.h) ──────────────────────────────

final class _CGPoint extends Struct {
  @Double()
  external double x;
  @Double()
  external double y;
}

final class _CGSize extends Struct {
  @Double()
  external double width;
  @Double()
  external double height;
}

final class _CGRect extends Struct {
  external _CGPoint origin;
  external _CGSize size;
}

final class _CGEvent extends Opaque {}

final class _CGEventSource extends Opaque {}

// ── Native signatures ───────────────────────────────────────────────────────

typedef _CGEventCreateMouseEventNative = Pointer<_CGEvent> Function(
  Pointer<_CGEventSource> source,
  Uint32 mouseType,
  _CGPoint mouseCursorPosition,
  Uint32 mouseButton,
);
typedef _CGEventCreateMouseEventDart = Pointer<_CGEvent> Function(
  Pointer<_CGEventSource> source,
  int mouseType,
  _CGPoint mouseCursorPosition,
  int mouseButton,
);

typedef _CGEventCreateScrollWheelEventNative = Pointer<_CGEvent> Function(
  Pointer<_CGEventSource> source,
  Uint32 units,
  Uint32 wheelCount,
  Int32 wheel1,
);
typedef _CGEventCreateScrollWheelEventDart = Pointer<_CGEvent> Function(
  Pointer<_CGEventSource> source,
  int units,
  int wheelCount,
  int wheel1,
);

typedef _CGEventPostNative = Void Function(Uint32 tap, Pointer<_CGEvent> event);
typedef _CGEventPostDart = void Function(int tap, Pointer<_CGEvent> event);

typedef _CFReleaseNative = Void Function(Pointer<Void> cf);
typedef _CFReleaseDart = void Function(Pointer<Void> cf);

typedef _AXIsProcessTrustedNative = Bool Function();
typedef _AXIsProcessTrustedDart = bool Function();

typedef _CGMainDisplayIDNative = Uint32 Function();
typedef _CGMainDisplayIDDart = int Function();

typedef _CGDisplayBoundsNative = _CGRect Function(Uint32 display);
typedef _CGDisplayBoundsDart = _CGRect Function(int display);

typedef _CGGetActiveDisplayListNative = Int32 Function(
  Uint32 maxDisplays,
  Pointer<Uint32> activeDisplays,
  Pointer<Uint32> displayCount,
);
typedef _CGGetActiveDisplayListDart = int Function(
  int maxDisplays,
  Pointer<Uint32> activeDisplays,
  Pointer<Uint32> displayCount,
);

typedef _CGEventCreateKeyboardEventNative = Pointer<_CGEvent> Function(
  Pointer<_CGEventSource> source,
  Uint16 virtualKey,
  Bool keyDown,
);
typedef _CGEventCreateKeyboardEventDart = Pointer<_CGEvent> Function(
  Pointer<_CGEventSource> source,
  int virtualKey,
  bool keyDown,
);

typedef _CGEventSetFlagsNative = Void Function(Pointer<_CGEvent> event, Uint64 flags);
typedef _CGEventSetFlagsDart = void Function(Pointer<_CGEvent> event, int flags);
