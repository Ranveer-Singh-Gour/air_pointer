// Classic web worker — MediaPipe HandLandmarker runs off the main thread.
//
// This file must stay a CLASSIC worker (no type:'module' on the Worker
// constructor). MediaPipe's Emscripten WASM runtime calls importScripts()
// internally; that API is only available in classic workers, not module workers.
// MediaPipe is loaded via dynamic import() instead, which is supported in
// classic workers since Chrome 80.
//
// Protocol (all messages are plain JSON-serialisable objects):
//   main → worker  { type: 'init', bundleUrl: string,
//                    wasmFolderUrl: string, modelUrl: string, numHands: number,
//                    minHandDetectionConfidence?: number,
//                    minHandPresenceConfidence?: number,
//                    minTrackingConfidence?: number }
//   main → worker  { type: 'detect',  frame: ImageBitmap, timestampMs: number }
//   main → worker  { type: 'setDebugEnabled', enabled: boolean }
//   main → worker  { type: 'dispose' }
//
//   worker → main  { type: 'ready' }
//   worker → main  { type: 'landmarks',
//                    hands: Array<Array<{x,y,z,visibility}>>,
//                    worldHands: Array<Array<{x,y,z,visibility}>>,
//                    handednesses: Array<'Left'|'Right'|'Unknown'>,
//                    timestampMs: number, workerLatencyMs: number }
//   worker → main  { type: 'error', message: string }
//
// worldHands/handednesses are only populated while debug mode is enabled
// (see 'setDebugEnabled' below) — the worker skips computing and
// transferring that data across the thread boundary until the main thread
// calls GestureInputSource.setDebugOverlayEnabled(true), which is
// independent of whether debugInfo has a listener (many consumers listen to
// debugInfo just for the cheap phase/dwellProgress/isPointing fields).
//
// Self-hosting: pass bundleUrl/wasmFolderUrl/modelUrl pointing to local assets
// (e.g. downloaded by scripts/download_mediapipe.sh into example/web/mediapipe/).
// CDN is the default when GestureInputSource is constructed without overrides.

let landmarker = null;
let initialized = false;
let debugEnabled = false;

self.onmessage = async (event) => {
  const { type } = event.data;

  // ── init ──────────────────────────────────────────────────────────────────
  if (type === 'init') {
    if (initialized) return;  // idempotent — ignore duplicate init messages
    initialized = true;
    try {
      // Dynamic import() keeps the ESM bundle while allowing importScripts()
      // to remain available for MediaPipe's WASM sub-worker threads.
      const { FilesetResolver, HandLandmarker } = await import(event.data.bundleUrl);
      const vision = await FilesetResolver.forVisionTasks(event.data.wasmFolderUrl);
      landmarker = await HandLandmarker.createFromOptions(vision, {
        baseOptions: {
          modelAssetPath: event.data.modelUrl,
          delegate: 'CPU',  // GPU conflicts with Flutter's WebGL context
        },
        runningMode: 'VIDEO',
        numHands: event.data.numHands ?? 2,
        minHandDetectionConfidence: event.data.minHandDetectionConfidence ?? 0.5,
        minHandPresenceConfidence: event.data.minHandPresenceConfidence ?? 0.5,
        minTrackingConfidence: event.data.minTrackingConfidence ?? 0.5,
      });
      self.postMessage({ type: 'ready' });
    } catch (e) {
      self.postMessage({ type: 'error', message: String(e) });
    }
    return;
  }

  // ── setDebugEnabled ──────────────────────────────────────────────────────
  if (type === 'setDebugEnabled') {
    debugEnabled = !!event.data.enabled;
    return;
  }

  // ── detect ────────────────────────────────────────────────────────────────
  if (type === 'detect') {
    const frame = event.data.frame;
    const timestampMs = event.data.timestampMs;
    const recvMs = Date.now();

    if (!landmarker) {
      frame?.close();
      // Always reply so the main thread's _workerBusy is cleared.
      self.postMessage({ type: 'landmarks', hands: [], handednesses: [], timestampMs, workerLatencyMs: 0 });
      return;
    }

    let hands = [];
    let worldHands = [];
    let handednesses = [];
    try {
      const result = landmarker.detectForVideo(frame, timestampMs);
      frame.close();  // free GPU memory immediately after detection
      hands = result.landmarks.map(hand =>
        hand.map(({ x, y, z, visibility }) => ({ x, y, z, visibility }))
      );
      if (debugEnabled) {
        worldHands = (result.worldLandmarks ?? []).map(hand =>
          hand.map(({ x, y, z, visibility }) => ({ x, y, z, visibility }))
        );
        // handednesses is an array-of-arrays; take the top category per hand.
        handednesses = (result.handednesses ?? []).map(
          cats => cats[0]?.categoryName ?? 'Unknown'
        );
      }
    } catch (_) {
      frame?.close();
      // Non-fatal — skipped frame. Reply with empty hands so lock is released.
    }

    self.postMessage({
      type: 'landmarks',
      hands,
      worldHands,
      handednesses,
      timestampMs,
      workerLatencyMs: Date.now() - recvMs,
    });
    return;
  }

  // ── dispose ───────────────────────────────────────────────────────────────
  if (type === 'dispose') {
    landmarker?.close();
    landmarker = null;
    self.close();
  }
};
