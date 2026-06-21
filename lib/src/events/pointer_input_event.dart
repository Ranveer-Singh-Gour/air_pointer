import 'package:flutter/painting.dart';

sealed class PointerInputEvent {
  const PointerInputEvent();
}

final class CanvasTapEvent extends PointerInputEvent {
  const CanvasTapEvent({required this.position});

  final Offset position;
}

final class CanvasDownEvent extends PointerInputEvent {
  const CanvasDownEvent({required this.position});

  final Offset position;
}

final class CanvasMoveEvent extends PointerInputEvent {
  const CanvasMoveEvent({required this.position});

  final Offset position;
}

final class CanvasUpEvent extends PointerInputEvent {
  const CanvasUpEvent({required this.position});

  final Offset position;
}

final class CanvasHoverEvent extends PointerInputEvent {
  const CanvasHoverEvent({required this.position});

  final Offset position;
}

final class CanvasScrollEvent extends PointerInputEvent {
  const CanvasScrollEvent({
    required this.position,
    required this.delta,
    this.isTrackpad = false,
  });

  final Offset position;
  final Offset delta;

  /// True when the scroll originated from a trackpad (e.g. macOS two-finger
  /// pan). The OS already applies momentum scrolling for trackpad events, so
  /// consumers should apply the delta directly rather than adding extra inertia.
  final bool isTrackpad;
}

final class CanvasScaleEvent extends PointerInputEvent {
  const CanvasScaleEvent({
    required this.focalPoint,
    required this.scaleDelta,
    required this.panDelta,
    this.rotation = 0.0,
  });

  final Offset focalPoint;

  /// Multiplicative scale factor: 1.05 = 5% zoom in, 0.95 = 5% zoom out.
  final double scaleDelta;
  final Offset panDelta;

  /// Rotation delta in radians; positive = clockwise in screen coordinates.
  final double rotation;
}

final class CanvasScaleEndEvent extends PointerInputEvent {
  const CanvasScaleEndEvent();
}

/// Emitted when a drag is interrupted by an unrecoverable event (e.g. the
/// hand tracking hand exits the camera frame mid-drag).
///
/// Unlike [CanvasUpEvent], cancel signals that the action should NOT be
/// committed — consumers should roll back or discard any in-progress change.
final class CanvasCancelEvent extends PointerInputEvent {
  const CanvasCancelEvent();
}

/// Cardinal direction of a [CanvasSwipeEvent].
enum SwipeDirection { up, down, left, right }

/// Emitted when the cursor moves fast enough in a single direction to be
/// classified as a swipe gesture.
///
/// Only fired by [GestureInputSource] when `swipeThreshold > 0`. The cursor
/// continues emitting [CanvasHoverEvent] alongside the swipe, so consumers
/// do not need to separately track position.
///
/// [velocity] is the cursor speed in screen pixels per second at the moment
/// the swipe was detected.
final class CanvasSwipeEvent extends PointerInputEvent {
  const CanvasSwipeEvent({required this.direction, required this.velocity});

  final SwipeDirection direction;

  /// Cursor speed in screen pixels per second.
  final double velocity;
}
