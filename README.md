# air_pointer

Platform-agnostic canvas input abstraction for Flutter. Ships a `MouseInputSource`
for mouse/trackpad/touch and a `GestureInputSource` powered by MediaPipe
HandLandmarker for touchless hand control (Flutter Web only), both unified behind
a single `CanvasInputController` — the canvas never knows which source the events
came from.

---

## Quick start

```dart
import 'package:air_pointer/air_pointer.dart';

class MyCanvasState extends State<MyCanvas> {
  late final CanvasInputController _controller;
  late final StreamSubscription<PointerInputEvent> _sub;

  @override
  void initState() {
    super.initState();
    _controller = CanvasInputController(
      sources: [
        MouseInputSource(),     // mouse, trackpad, touch
        GestureInputSource(),   // MediaPipe hand tracking (web only; no-op elsewhere)
      ],
    );
    _sub = _controller.events.listen(_onInput);
  }

  void _onInput(PointerInputEvent event) {
    switch (event) {
      case CanvasDownEvent(:final position):
        // finger/cursor pressed (or pinch started)
      case CanvasMoveEvent(:final position):
        // drag in progress
      case CanvasUpEvent(:final position):
        // released — commit the action
      case CanvasCancelEvent():
        // drag interrupted (e.g. hand left the camera mid-drag) — discard it
      case CanvasTapEvent(:final position):
        // resolved tap (gesture arena winner, no drag)
      case CanvasHoverEvent(:final position):
        // cursor hovering (no button held)
      case CanvasScrollEvent(:final position, :final delta):
        // scroll wheel
      case CanvasScaleEvent(:final focalPoint, :final scaleDelta, :final panDelta):
        // pinch-to-zoom (two fingers or two hands)
      case CanvasScaleEndEvent():
        // scale gesture ended
    }
  }

  @override
  Widget build(BuildContext context) => _controller.buildSurface(
        child: MyCanvasPainter(...),
      );

  @override
  void dispose() {
    unawaited(_sub.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }
}
```

---

## GestureInputSource (Flutter Web only)

### 1. Add the MediaPipe CDN script

In `web/index.html`, before `flutter_bootstrap.js`:

```html
<script src="https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.21/vision_bundle.js"
        crossorigin="anonymous"></script>
<script src="flutter_bootstrap.js" async></script>
```

### 2. Copy the worker script

Place `hand_tracker_worker.js` (from `example/web/`) next to your
`index.html`. The worker runs MediaPipe inference off the main thread.

### 3. Initialize the source

```dart
final _gestureSource = GestureInputSource(
  onError: (e, st) => print('hand tracking: $e'),
);

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // Pass the canvas size so cursor coordinates are in screen pixels.
  _gestureSource.updateCanvasSize(MediaQuery.sizeOf(context));
  unawaited(_gestureSource.initialize());
}
```

`initialize()` is idempotent — safe to call from `didChangeDependencies`.

### Gesture mapping

| Gesture | Event |
|---|---|
| Open hand, fingertip moves | `CanvasHoverEvent` |
| Pinch (thumb + index <5 % gap) | `CanvasDownEvent` |
| Hold pinch + move | `CanvasMoveEvent` |
| Release pinch | `CanvasUpEvent` |
| Hand exits frame mid-drag | `CanvasCancelEvent` (discard, not commit) |
| Two-hand spread/pinch | `CanvasScaleEvent` |
| Two hands separate | `CanvasScaleEndEvent` |

Position is smoothed with a `OneEuroFilter` and the x-axis is mirrored so
motion feels natural facing the front camera.

### Camera preview

```dart
_gestureSource.buildCameraPreview(width: 240, height: 180)
```

Returns a widget with a live mirrored feed. Shows a placeholder until the
camera is ready, and an error card if initialization failed.

### Debug overlay

Subscribe to `GestureInputSource.debugInfo` for per-frame `GestureDebugInfo`
snapshots (phase, pinch distance, landmarks, latency). Use them to build a
custom debug overlay — the example app (`example/`) has a ready-made one.

---

## Per-user calibration

Default thresholds (pinch close = 0.05, open = 0.08) work for most hands in
good lighting. For users with small hands, unusual skin tone, or dim
environments, run a quick calibration:

```dart
// 1. Collect samples via GestureCalibrator (reads pinch distance from debugInfo).
final calibrator = GestureCalibrator();

// Call addOpenSample / addCloseSample each frame from your debugInfo subscription:
// calibrator.addOpenSample(info.pinchDistance);   // while hand is open
// calibrator.addCloseSample(info.pinchDistance);  // while hand is pinching

// 2. Compute thresholds when both poses are collected.
final result = calibrator.compute(); // null if insufficient data
if (result != null) {
  gestureSource.applyCalibration(result);
}
```

The example app ships a `CalibrationDialog` widget that handles the full
guided flow.

---

## Architecture boundary

The strict invariant: **no `NormalizedLandmark`, `HandLandmarker`, `JSObject`,
or any `dart:js_interop` type may appear outside `lib/src/gesture/`**. The
`PointerInputEvent` sealed hierarchy is the only currency that crosses the
boundary — all sources speak the same type.

---

## Event type reference

| Type | Fields | Description |
|---|---|---|
| `CanvasTapEvent` | `position` | Resolved tap (no drag) |
| `CanvasDownEvent` | `position` | Drag/pinch started |
| `CanvasMoveEvent` | `position` | Drag in progress |
| `CanvasUpEvent` | `position` | Drag ended — commit |
| `CanvasCancelEvent` | — | Drag aborted — discard |
| `CanvasHoverEvent` | `position` | Hover (no press) |
| `CanvasScrollEvent` | `position`, `delta` | Scroll wheel |
| `CanvasScaleEvent` | `focalPoint`, `scaleDelta`, `panDelta` | Pinch/spread |
| `CanvasScaleEndEvent` | — | Scale gesture ended |

---

## Known limitations

- **Flutter Web only for gestures.** `GestureInputSource` is a no-op on iOS,
  Android, macOS, Windows, and Linux. There is no native camera/ML integration.

- **Requires a secure context.** `getUserMedia` only works on `https://` or
  `localhost`. Serving over plain `http://` will produce a camera permission
  error.

- **Single-hand tracking.** MediaPipe HandLandmarker is configured for
  `numHands: 2` for the two-hand spread gesture, but the pinch/drag pipeline
  only tracks the first detected hand. Left/right handedness is not
  distinguished.

- **Lighting sensitivity.** Tracking degrades in dim or strongly backlit
  conditions. MediaPipe's model is generally robust across skin tones but
  performance may vary. Run calibration if default thresholds are unreliable.

- **No offline/self-hosted model.** The WASM runtime and `.task` model file
  are loaded from CDN at runtime. Self-hosting is possible by downloading the
  assets and updating the paths in `GestureInputSource` — not yet wired as a
  package option.

- **First-run CDN latency.** MediaPipe WASM (~4 MB) loads before the first
  frame is processed. On a cold cache this takes 2–5 seconds. Subsequent page
  loads use the browser cache.

- **`CanvasCancelEvent` has no position.** When a hand exits the frame
  mid-drag, the last known position is not re-emitted. Consumers that need a
  "cancel at position" snapshot should cache `_lastPosition` from the preceding
  `CanvasMoveEvent`.
