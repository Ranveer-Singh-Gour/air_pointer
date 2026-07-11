import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/services.dart';

import '../native/cursor_backend.dart';
import 'gesture_action_executor.dart';
import 'system_shortcut.dart';

/// Translates a [PointerInputEvent] stream into real OS cursor
/// move/click/drag/scroll via [CursorBackend].
///
/// Mapping: [CanvasDownEvent]/[CanvasMoveEvent]/[CanvasUpEvent] drive
/// click+drag, [CanvasHoverEvent] moves the cursor without a button,
/// [CanvasScrollEvent] scrolls, [CanvasCancelEvent] drops in-progress drag
/// state without posting an up-click.
///
/// [CanvasTapEvent]/[CanvasDoubleTapEvent] are intentionally NOT mapped —
/// those come only from the dwell-click path, which the caller should leave
/// at its zero-duration default so pinch (down/move/up) is the only click
/// source; enabling dwell here would mean "hold the cursor still over any
/// system UI -> real click," a much bigger false-positive surface than
/// inside a Flutter canvas.
///
/// [CanvasSwipeEvent] and [CanvasScaleEvent] are approximated, not
/// literally reproduced — neither macOS nor Windows has a public API to
/// post synthetic trackpad swipe/pinch gestures, so swipes fire built-in
/// space-switching shortcuts and two-hand pinch fires discrete zoom-modifier
/// scroll steps once the accumulated scale crosses [_zoomStepFactor],
/// rather than tracking continuously. [CanvasGestureEvent] (a discrete pose
/// like thumbs-up) runs whatever [gestureActions] binds it to, if anything.
class SystemCursorSink {
  SystemCursorSink(
    Stream<PointerInputEvent> events, {
    this.clickSoundEnabled = true,
    Map<RecognizedGesture, GestureAction>? gestureActions,
    GestureActionExecutor? actionExecutor,
  })  : gestureActions = gestureActions ?? const {},
        _actionExecutor = actionExecutor ?? GestureActionExecutor(),
        // `GestureSessionController` sizes the canvas from `combinedDisplayBounds`,
        // whose origin is (0, 0) only when every display sits at/right-of and
        // below the main one. A monitor to the left of or above main gives a
        // negative origin in that global coordinate space — this offset
        // translates canvas-local positions (which start at (0, 0)) back into
        // that space so clicks land on the display the hand is actually over.
        _originOffset = CursorBackend.instance.combinedDisplayBounds.topLeft {
    _sub = events.listen(_onEvent);
  }

  /// Multiplicative accumulated-scale threshold that fires one discrete zoom
  /// step (matches [CanvasScaleEvent.scaleDelta]'s own "1.05 = 5% zoom"
  /// doc scale — a sustained ~15% pinch reads as one step).
  static const _zoomStepFactor = 1.15;

  /// Whether a click sound plays on [CanvasDownEvent] (pinch-close). Purely
  /// audible feedback — does not affect cursor behavior. Mutable so a
  /// settings toggle can flip it without recreating the sink.
  bool clickSoundEnabled;

  /// Maps a discrete [RecognizedGesture] to the [GestureAction] it triggers.
  /// Gestures with no entry are ignored. Mutable so a settings screen can
  /// rebind actions without recreating the sink.
  Map<RecognizedGesture, GestureAction> gestureActions;

  final GestureActionExecutor _actionExecutor;
  final _backend = CursorBackend.instance;
  final Offset _originOffset;
  StreamSubscription<PointerInputEvent>? _sub;
  bool _dragging = false;
  double _accumulatedScale = 1.0;

  Offset _toGlobal(Offset canvasPosition) => canvasPosition + _originOffset;

  void _onEvent(PointerInputEvent event) {
    switch (event) {
      case CanvasDownEvent(:final position):
        _dragging = true;
        _backend.mouseDown(_toGlobal(position));
        if (clickSoundEnabled) unawaited(SystemSound.play(SystemSoundType.click));

      case CanvasMoveEvent(:final position):
        if (_dragging) {
          _backend.mouseDragged(_toGlobal(position));
        } else {
          _backend.moveTo(_toGlobal(position));
        }

      case CanvasHoverEvent(:final position):
        _backend.moveTo(_toGlobal(position));

      case CanvasUpEvent(:final position):
        _dragging = false;
        _backend.mouseUp(_toGlobal(position));

      case CanvasScrollEvent(:final delta):
        _backend.scroll(-delta.dy);

      case CanvasCancelEvent():
        _dragging = false;

      case CanvasScaleEvent(:final scaleDelta):
        _accumulatedScale *= scaleDelta;
        if (_accumulatedScale >= _zoomStepFactor) {
          _backend.scroll(40, zoomModifier: true); // zoom in
          _accumulatedScale = 1.0;
        } else if (_accumulatedScale <= 1 / _zoomStepFactor) {
          _backend.scroll(-40, zoomModifier: true); // zoom out
          _accumulatedScale = 1.0;
        }

      case CanvasScaleEndEvent():
        _accumulatedScale = 1.0;

      case CanvasSwipeEvent(:final direction):
        _actionExecutor.run(SystemShortcutAction(switch (direction) {
          SwipeDirection.left => SystemShortcut.spaceLeft,
          SwipeDirection.right => SystemShortcut.spaceRight,
          SwipeDirection.up => SystemShortcut.missionControl,
          SwipeDirection.down => SystemShortcut.appExpose,
        }));

      case CanvasGestureEvent(:final gesture, :final isSecondHand):
        if (isSecondHand) break; // only the primary hand triggers actions
        final action = gestureActions[gesture];
        if (action != null) _actionExecutor.run(action);

      case CanvasTapEvent():
      case CanvasDoubleTapEvent():
      case CanvasLongPressEvent():
        break; // unmapped here, see class doc comment
    }
  }

  void dispose() {
    unawaited(_sub?.cancel());
  }
}
