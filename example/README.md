# air_pointer example

Demo app for [`air_pointer`](../README.md), showing mouse, touch, stylus, and
MediaPipe hand-gesture input unified behind one `CanvasInputController`.

## Running

Hand tracking needs a camera and a secure context, so run in Chrome:

```sh
flutter run -d chrome
```

Grant camera permission when prompted. Everything except hand tracking also
works on native targets (`flutter run -d macos`, etc.).

## Demos

The app is organised into three tabs (see `lib/main.dart`):

- **Netflix Demo** (`lib/src/netflix_canvas.dart`) — a browse-style grid you
  can point at, hover, and select with pinch gestures; includes dwell-to-click
  and a calibration screen (`lib/src/calibration_screen.dart`) for tuning
  pinch thresholds to your hand.
- **Sandbox** (`lib/src/sandbox_canvas.dart`) — a free-form canvas with
  draggable boxes (`lib/src/draggable_box.dart`) for exercising every
  `PointerInputEvent` type: tap, double-tap, long-press, drag, scroll,
  scale, swipe, and discrete gestures.
- **Room 3D** (`lib/src/room_3d_canvas.dart`) — an AR/VR-style interactive
  room where you move the camera and rotate furniture with hand gestures.

## MediaPipe assets

By default the MediaPipe WASM runtime and hand model load from CDN, and the
inference worker is served from `web/hand_tracker_worker.js` — no setup needed.

To run fully offline (or behind a strict CSP), download the pinned assets:

```sh
../scripts/download_mediapipe.sh
```

This populates `web/mediapipe/` (gitignored), which `GestureInputSource` can
use via `mediaPipeBaseUrl` / `modelAssetUrl` — see
[Self-hosting MediaPipe assets](../README.md#self-hosting-mediapipe-assets-flutter-web-only).
