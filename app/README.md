# air_pointer_app

A menu-bar app that controls the real system cursor with hand gestures, seen
through the webcam: move your hand to move the cursor, pinch to click/drag,
two-finger-point to scroll. Works across every app, not just inside a
Flutter canvas. **macOS is the real, working platform** — see Platform
support below for what Windows actually has.

Built on the `air_pointer` package (path dependency to `../`) — all gesture
recognition, calibration, and cursor smoothing comes from there unchanged.
This app supplies the two pieces that package intentionally doesn't:

- A native hand-tracking backend, via `LandmarkProvider` — macOS uses
  Apple's Vision framework (`VNDetectHumanHandPoseRequest`); Windows has no
  real implementation yet (see below).
- A way to drive the *real* OS cursor — `CursorBackend`, implemented with
  `dart:ffi` into CoreGraphics' `CGEventPost` on macOS and `user32.dll`'s
  `SendInput` on Windows.

Not published as part of the `air_pointer` package (see the repo-root
`.pubignore`) — it's a standalone product, not library code.

## Platform support

| | macOS | Windows |
|---|---|---|
| Hand tracking | Real (Vision framework) | **Stub only** — `WindowsLandmarkProvider` never detects a hand, see its doc comment |
| Cursor/click/drag/scroll | Real (`MacosCursorBackend`, CoreGraphics) | Real code, **never built or run** — no Windows machine in this environment |
| Keyboard-shortcut actions | Real | Real code, **never built or run** |
| Tray/window/settings/permissions | Real | Untested — `flutter build windows` has never been invoked here |

Windows was deliberately scoped to *"scaffold, not tracking"*: the
`CursorBackend`/`SendInput` and keyboard-injection code is written with the
same rigor as the macOS CoreGraphics bindings (using `package:win32`'s
maintained `INPUT`/`MOUSEINPUT`/`KEYBDINPUT` struct bindings rather than
hand-rolled FFI struct layouts, which have historically tricky x64
padding), but there is no Windows machine anywhere in this project's
development environment — none of it has ever compiled or run. Treat
`app/windows/` and every `windows_*.dart` file as unverified until someone
builds it on real Windows hardware.

The honest reason hand tracking is stubbed rather than attempted: Windows
has no OS-bundled hand-pose API equivalent to Vision. The most credible path
would reuse the `air_pointer` web platform's already-shipped MediaPipe Tasks
Vision WASM bundle inside an embedded WebView, bridging camera frames in and
landmarks out via JS messaging — a substantial, standalone piece of work
(see `WindowsLandmarkProvider`'s doc comment), not attempted here.

## Status

v0 complete, plus a second pass adding trust/safety and polish features:

- Menu-bar app with onboarding (camera + Accessibility permission flow),
  calibration, and cursor move/click/drag/scroll driven by real hand
  tracking.
- Calibration (pinch thresholds) and cursor-smoothing filter params persist
  across restarts (`AppSettingsStore`, NSUserDefaults-backed).
- Audible click feedback (`SystemSound.play`) on pinch, toggleable.
- Tray icon reflects live tracking status (initializing/tracking/lost/error),
  not just on/off.
- "Open at login" toggle (`launch_at_startup`, `SMAppService`-backed).
- Global panic hotkey (Control+Shift+Escape, `hotkey_manager`) instantly
  stops tracking from anywhere, even when the app isn't focused.
- Multi-monitor cursor placement (`CGGetActiveDisplayList`, with the
  origin-offset correction a naive union-of-bounds approach misses on
  monitor arrangements with a negative-origin display).
- Two-hand pinch-to-zoom and swipe gestures — **approximated, not literal**:
  macOS has no public API to post synthetic trackpad pinch/swipe gestures,
  so these fire discrete Cmd+scroll zoom steps and Control+Arrow
  space-switching shortcuts instead of continuous gesture data. Off by
  default (Settings → Gestures).
- Discrete gesture → action binding (Settings → Gesture actions), each
  action one of: a system shortcut, launching an app, or running an
  arbitrary command. E.g. bind thumbs-up to Mission Control. Required fixing
  `VisionLandmarkProvider` to actually run the package's `classifyGesture`
  heuristic over Vision's landmarks — it previously left `detectedGesture`
  at its default `none`, so `CanvasGestureEvent` could never fire for this
  backend.
- Windows scaffold (app shell, cursor/keyboard injection code) — see
  Platform support above for exactly what is and isn't real there.

**Not attempted — explicitly out of scope for this repo:**
- **Windows hand tracking**: see Platform support above.
- **Notarized release / Sparkle auto-update**: both need an Apple Developer
  account's credentials this repo doesn't have (see Distribution below) —
  Sparkle specifically is meaningless without the signing that notarization
  already requires.

See `/Users/zml-mac-ranveerg-01/.claude/plans/snazzy-mapping-lamport.md` for
the original v0 build plan.

### Known verification gap

The Vision-framework coordinate assumptions (`flipX`/`flipY` in
`CameraHandTracker.swift`) and the core hand-tracking behavior (mirroring,
calibration completing, cursor landing where expected, click/drag/scroll
actually working) have not been confirmed against a real hand by a human —
only build-and-launch (process stays alive, no crash log, registers as a
background/accessory process) has been verified in this environment. Try it
against a real camera before relying on it.

## Requirements

Runs outside the Mac App Store — App Sandbox is incompatible with the
Accessibility API this app depends on to post synthetic cursor events (both
`DebugProfile.entitlements` and `Release.entitlements` have
`com.apple.security.app-sandbox` set to `false`). Needs Camera and
Accessibility permission, granted through the app's own onboarding flow on
first "Enable."

## Development

```
cd app
flutter run -d macos
```

The app is a menu-bar/tray app — `flutter run` will still open a window on
launch (useful for hot reload during development); the built `.app` from
`flutter build macos` behaves as a true background app with no Dock icon
and no window until opened from the tray.

## Distribution (manual steps — need an Apple Developer account)

App Sandbox is off (required for this app's Accessibility/CGEvent usage —
see Requirements above). Hardened Runtime is deliberately *not* baked into
the Xcode project's `ENABLE_HARDENED_RUNTIME` build setting: turning that on
made local, ad-hoc/unsigned `flutter build macos --release` builds fail to
launch at startup (`dyld: Library not loaded ... code signature` on an
embedded plugin framework) — Hardened Runtime's stricter dyld validation
needs every embedded framework properly signed as one coherent unit, which
only a real Developer ID signing pass provides. Apply it at sign time
instead (`codesign --options runtime` below), which only affects the
distributed build, not local development ones. What's left needs
credentials this repo doesn't have:

1. **Developer ID Application certificate** — from your Apple Developer
   account (paid membership required), installed in your login keychain.
2. **Sign the release build** (this is also where Hardened Runtime gets
   turned on, via `--options runtime`):
   ```
   flutter build macos --release
   codesign --deep --force --options runtime \
     --sign "Developer ID Application: <Your Name/Org> (<TEAMID>)" \
     build/macos/Build/Products/Release/air_pointer_app.app
   ```
3. **Notarize**: create a notarytool credentials profile once
   (`xcrun notarytool store-credentials`, needs an app-specific password or
   API key from your Apple ID), then:
   ```
   ditto -c -k --keepParent build/macos/Build/Products/Release/air_pointer_app.app air_pointer_app.zip
   xcrun notarytool submit air_pointer_app.zip --keychain-profile "<profile-name>" --wait
   xcrun stapler staple build/macos/Build/Products/Release/air_pointer_app.app
   ```
4. Distribute the stapled `.app` zipped, or wrapped in a `.dmg` — not
   through the Mac App Store (see Requirements above).
