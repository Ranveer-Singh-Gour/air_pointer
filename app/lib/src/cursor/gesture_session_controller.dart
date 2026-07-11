import 'package:air_pointer/air_pointer.dart';

import '../native/system_cursor_ffi.dart';
import '../native/vision_landmark_provider.dart';
import 'gesture_action_executor.dart';
import 'system_cursor_sink.dart';

/// Owns the `GestureInputSource` (Vision-backed) and the `SystemCursorSink`
/// subscription lifecycle. `canvasSize` is set from every active display's
/// combined bounds (see `SystemCursorFfi.combinedDisplayBounds`), so
/// `PointerInputEvent.position` values span the whole desktop, not just the
/// main display.
///
/// Cursor control (`SystemCursorSink`) is a separate on/off switch from
/// tracking itself: tracking can run (camera on, `debugInfo`/preview live)
/// while cursor control is off, so calibration and verification can happen
/// without the real cursor moving.
class GestureSessionController {
  GestureSessionController({
    void Function(Object, StackTrace)? onError,
    bool swipeGesturesEnabled = false,
    bool twoHandZoomEnabled = false,
    this.clickSoundEnabled = true,
    Map<RecognizedGesture, GestureAction> gestureActions = const {},
  })  : gestureActions = Map.of(gestureActions),
        source = GestureInputSource(
          landmarkProvider: VisionLandmarkProvider(),
          scrollEnabled: true,
          maxHands: twoHandZoomEnabled ? 2 : 1,
          swipeThreshold: swipeGesturesEnabled ? kDefaultSwipeThreshold : 0.0,
          onError: onError,
        ) {
    source.updateCanvasSize(SystemCursorFfi.instance.combinedDisplayBounds.size);
  }

  /// Screen-pixels-per-second swipe speed that counts as a swipe — matches
  /// the recognizer's own doc default for "fast, deliberate" motion.
  static const kDefaultSwipeThreshold = 800.0;

  final GestureInputSource source;
  bool clickSoundEnabled;
  Map<RecognizedGesture, GestureAction> gestureActions;
  SystemCursorSink? _sink;

  bool get cursorControlEnabled => _sink != null;

  /// Starts hand tracking (turns the camera on). Does not by itself move
  /// the real cursor — call [setCursorControlEnabled] separately.
  Future<void> start() => source.initialize();

  /// Updates click-sound feedback, including on an already-live sink —
  /// unlike [swipeGesturesEnabled]/[twoHandZoomEnabled] this doesn't require
  /// recreating [source].
  void setClickSoundEnabled(bool enabled) {
    clickSoundEnabled = enabled;
    _sink?.clickSoundEnabled = enabled;
  }

  /// Binds or clears the action a discrete gesture triggers. Takes effect
  /// immediately on an already-live sink — [gestureActions] is the same
  /// `Map` instance handed to [SystemCursorSink], mutated in place.
  void setGestureAction(RecognizedGesture gesture, GestureAction? action) {
    if (action == null) {
      gestureActions.remove(gesture);
    } else {
      gestureActions[gesture] = action;
    }
  }

  void setCursorControlEnabled(bool enabled) {
    if (enabled == cursorControlEnabled) return;
    if (enabled) {
      _sink = SystemCursorSink(
        source.events,
        clickSoundEnabled: clickSoundEnabled,
        gestureActions: gestureActions,
      );
    } else {
      _sink?.dispose();
      _sink = null;
    }
  }

  void dispose() {
    _sink?.dispose();
    source.dispose();
  }
}
