import 'dart:async';

import 'package:air_pointer/air_pointer.dart';
import 'package:flutter/services.dart';

import '../native/system_cursor_ffi.dart';
import 'gesture_action_executor.dart';

/// Translates a [PointerInputEvent] stream into real macOS cursor
/// move/click/drag/scroll via [SystemCursorFfi].
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
/// macOS UI -> real click," a much bigger false-positive surface than
/// inside a Flutter canvas.
///
/// [CanvasSwipeEvent] and [CanvasScaleEvent] are approximated, not
/// literally reproduced — macOS has no public API to post synthetic
/// trackpad swipe/pinch gestures, so swipes fire built-in space-switching
/// shortcuts and two-hand pinch fires discrete Cmd+scroll zoom steps once
/// the accumulated scale crosses [_zoomStepFactor], rather than tracking
/// continuously. [CanvasGestureEvent] (a discrete pose like thumbs-up) runs
/// whatever [gestureActions] binds it to, if anything.
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
        // negative origin in CGEvent's global coordinate space — this offset
        // translates canvas-local positions (which start at (0, 0)) back into
        // that space so clicks land on the display the hand is actually over.
        _originOffset = SystemCursorFfi.instance.combinedDisplayBounds.topLeft {
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
  final _ffi = SystemCursorFfi.instance;
  final Offset _originOffset;
  StreamSubscription<PointerInputEvent>? _sub;
  bool _dragging = false;
  double _accumulatedScale = 1.0;

  Offset _toGlobal(Offset canvasPosition) => canvasPosition + _originOffset;

  void _onEvent(PointerInputEvent event) {
    switch (event) {
      case CanvasDownEvent(:final position):
        _dragging = true;
        _ffi.mouseDown(_toGlobal(position));
        if (clickSoundEnabled) unawaited(SystemSound.play(SystemSoundType.click));

      case CanvasMoveEvent(:final position):
        if (_dragging) {
          _ffi.mouseDragged(_toGlobal(position));
        } else {
          _ffi.moveTo(_toGlobal(position));
        }

      case CanvasHoverEvent(:final position):
        _ffi.moveTo(_toGlobal(position));

      case CanvasUpEvent(:final position):
        _dragging = false;
        _ffi.mouseUp(_toGlobal(position));

      case CanvasScrollEvent(:final delta):
        _ffi.scroll(-delta.dy);

      case CanvasCancelEvent():
        _dragging = false;

      case CanvasScaleEvent(:final scaleDelta):
        _accumulatedScale *= scaleDelta;
        if (_accumulatedScale >= _zoomStepFactor) {
          _ffi.scroll(40, cmdModifier: true); // zoom in
          _accumulatedScale = 1.0;
        } else if (_accumulatedScale <= 1 / _zoomStepFactor) {
          _ffi.scroll(-40, cmdModifier: true); // zoom out
          _accumulatedScale = 1.0;
        }

      case CanvasScaleEndEvent():
        _accumulatedScale = 1.0;

      case CanvasSwipeEvent(:final direction):
        _actionExecutor.run(switch (direction) {
          SwipeDirection.left => GestureAction.spaceLeft,
          SwipeDirection.right => GestureAction.spaceRight,
          SwipeDirection.up => GestureAction.missionControl,
          SwipeDirection.down => GestureAction.appExpose,
        });

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
