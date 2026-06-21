## 0.1.0

Initial release.

### Events

- **`PointerInputEvent` sealed hierarchy** — `CanvasTapEvent`, `CanvasDownEvent`,
  `CanvasMoveEvent`, `CanvasUpEvent`, `CanvasCancelEvent`, `CanvasHoverEvent`,
  `CanvasScrollEvent` (with `isTrackpad`), `CanvasScaleEvent` (with `rotation`),
  `CanvasScaleEndEvent`, `CanvasSwipeEvent` (with `SwipeDirection` and `velocity`).
  All events use the `Canvas` prefix to avoid collisions with Flutter's own pointer events.

### Core abstractions

- **`CanvasInputSource`** — abstract boundary; all input origins implement this contract.
- **`CanvasInputController`** — merges events from multiple `CanvasInputSource`s into a
  single broadcast stream; folds `buildSurface` wrappers in order.

### MouseInputSource

- Maps Flutter gesture-arena callbacks to canvas events: tap → `CanvasTapEvent`,
  one-finger drag → Down/Move/Up, two-finger pinch → `CanvasScaleEvent`, scroll wheel
  and native trackpad pinch (`PointerScaleEvent`) → `CanvasScrollEvent` /
  `CanvasScaleEvent`, mouse hover → `CanvasHoverEvent`.
- `scrollMultiplier` — scales scroll deltas before emission.
- `tapSlop` — configurable tap-slop threshold (default 10 px).
- `isTrackpad` on `CanvasScrollEvent` — true for macOS/iOS two-finger pan; consumers can
  skip ticker-based inertia since the OS already provides momentum.

### GestureInputSource (Flutter Web)

MediaPipe HandLandmarker running in a dedicated web worker (off the main thread).
Zero-copy `ImageBitmap` transfer. Camera permission / hardware / context errors all
produce typed `HandTrackingStatus` states.

- **`HandGestureRecognizer`** — pure-Dart state machine; fully testable without a camera.
  - Acquisition gate: N consecutive frames (default 3) to confirm hand presence.
  - Hysteresis: separate close (default 0.05) and open (default 0.08) thresholds prevent
    chatter near the boundary.
  - Grace window: N frames (default 5) before declaring the hand lost; cursor freezes and
    dwell progress is preserved through brief occlusions.
  - Clutch / Midas-touch guard: pinch is blocked until the hand opens after confirmation,
    preventing accidental drags when the hand enters the frame already pinched.
  - `CanvasCancelEvent` (not `CanvasUpEvent`) when the hand exits during an active drag.
  - Two-hand spread → `CanvasScaleEvent` with rotation delta;
    `CanvasScaleEndEvent` when the second hand leaves.
  - Dwell-click: cursor must hold still within `dwellRadius` for `dwellDuration` to emit
    `CanvasTapEvent`. Progress is reported via `GestureDebugInfo.dwellProgress` (0–1).
    Dwell is preserved through the grace window so brief occlusions don't reset progress.
  - Pointing-finger scroll: index extended + middle curled → `CanvasScrollEvent` driven by
    vertical fingertip movement. Enabled via `scrollEnabled: true`; scaled by `scrollScale`.
  - Swipe gesture: fast directional movement (velocity > `swipeThreshold` px/s) in an
    open hand emits `CanvasSwipeEvent`. 60/40 dominance ratio prevents diagonal
    false-positives; 400 ms cooldown suppresses repeated firing from one gesture.
    Disabled by default (`swipeThreshold: 0`).
- **`OneEuroFilter`** — adaptive low-pass filter (Casiez et al., CHI 2012) for landmark
  coordinates. Exposes `velocity` for prediction and swipe detection.
- **`GestureCalibrator`** — accumulates open/closed pose samples from
  `GestureDebugInfo.pinchDistance` and computes per-user `CalibrationResult`.
- **`LandmarkProvider`** — platform interface for native landmark sources (e.g. TFLite on
  iOS/Android); web implementation uses MediaPipe via web worker.
- **Debug support** — `GestureInputSource.debugInfo` stream of `GestureDebugInfo`
  (phase, pinch distance, dwell progress, pointing flag, landmarks, worker latency,
  round-trip latency). `buildCameraPreview` returns a live camera widget.

### Example

`example/` ships two demos driven entirely through `CanvasInputController`:

- **Sandbox canvas** — draggable boxes with dot-grid background, inertia scrolling,
  two-finger pinch-to-zoom, dwell-click, pointing-finger scroll, debug overlay,
  camera preview, calibration dialog, and zoom badge.
- **Netflix-style demo** — scrollable content grid with hero section, card rows with
  horizontal scrolling, detail overlay, and full air-pointer interaction (pinch-drag with
  inertia, dwell-click with progress ring, pointing scroll, swipe navigation).
