## 0.1.0

Initial release.

### Core

- **`PointerInputEvent` sealed hierarchy** — `CanvasTapEvent`, `CanvasDownEvent`,
  `CanvasMoveEvent`, `CanvasUpEvent`, `CanvasCancelEvent`, `CanvasHoverEvent`,
  `CanvasScrollEvent`, `CanvasScaleEvent`, `CanvasScaleEndEvent`. All events use the
  `Canvas` prefix to avoid collisions with Flutter's own `PointerDownEvent` etc.

- **`CanvasInputSource` interface** — abstract boundary; all input origins
  implement this contract.

- **`CanvasInputController`** — merges events from multiple `CanvasInputSource`s
  into a single broadcast stream; folds `buildSurface` wrappers in order.

- **`MouseInputSource`** — maps Flutter gesture arena callbacks to canvas events:
  tap → `CanvasTapEvent`, one-finger drag → Down/Move/Up, two-finger pinch →
  `CanvasScaleEvent`, scroll wheel → `CanvasScrollEvent`, mouse hover →
  `CanvasHoverEvent`.

- **`GestureInputSource`** (Flutter Web only) — MediaPipe HandLandmarker running in
  a dedicated web worker (off the main thread). Zero-copy `ImageBitmap` transfer.
  Camera permission/hardware/context errors all produce user-visible states.

- **`HandGestureRecognizer`** — pure-Dart state machine; testable without camera.
  - Acquisition gate: 3 consecutive frames to confirm hand presence.
  - Hysteresis: separate close (0.05) and open (0.08) thresholds prevent chatter.
  - Grace window: 5 frames before declaring hand lost; cursor freezes during grace.
  - Clutch / Midas-touch guard: pinch blocked until hand opens after confirmation.
  - `CanvasCancelEvent` (not `CanvasUpEvent`) when hand exits during a drag.
  - Two-hand spread → `CanvasScaleEvent`; `CanvasScaleEndEvent` when second hand leaves.

- **`OneEuroFilter`** — low-latency position smoother for landmark coordinates.

- **`GestureCalibrator`** — accumulates open/closed pose samples from
  `GestureDebugInfo.pinchDistance` and computes per-user `CalibrationResult`.

- **`CalibrationResult`** — value type for calibrated thresholds; applied via
  `GestureInputSource.applyCalibration`.

- **Debug support** — `GestureInputSource.debugInfo` stream of `GestureDebugInfo`
  (phase, pinch distance, landmarks, latency). Example app ships a
  `CalibrationDialog` and a skeleton + pinch-bar debug overlay.

### Example

`example/` — draggable boxes canvas driven entirely through
`CanvasInputController`. Demonstrates mouse drag, two-finger trackpad pinch, hand
hover/drag/zoom, debug overlay, camera preview, and calibration dialog.
