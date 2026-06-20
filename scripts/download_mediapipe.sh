#!/usr/bin/env bash
# Downloads the MediaPipe WASM runtime and hand_landmarker model into
# example/web/mediapipe/ so the example can run without CDN access.
#
# Usage:
#   bash scripts/download_mediapipe.sh
#
# After running, pass these to GestureInputSource:
#   mediaPipeBaseUrl: '/mediapipe'
#   modelAssetUrl:    '/mediapipe/models/hand_landmarker.task'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/../example/web/mediapipe"
VERSION="0.10.21"
CDN_BASE="https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VERSION}"
MODEL_URL="https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"

echo "Downloading MediaPipe ${VERSION} → ${OUT_DIR}"
echo ""

mkdir -p "${OUT_DIR}/wasm"
mkdir -p "${OUT_DIR}/models"

echo "  vision_bundle.mjs"
curl -fL --progress-bar "${CDN_BASE}/vision_bundle.mjs" \
  -o "${OUT_DIR}/vision_bundle.mjs"

echo "  wasm/vision_wasm_internal.js"
curl -fL --progress-bar "${CDN_BASE}/wasm/vision_wasm_internal.js" \
  -o "${OUT_DIR}/wasm/vision_wasm_internal.js"

echo "  wasm/vision_wasm_internal.wasm"
curl -fL --progress-bar "${CDN_BASE}/wasm/vision_wasm_internal.wasm" \
  -o "${OUT_DIR}/wasm/vision_wasm_internal.wasm"

echo "  wasm/vision_wasm_nosimd_internal.js"
curl -fL --progress-bar "${CDN_BASE}/wasm/vision_wasm_nosimd_internal.js" \
  -o "${OUT_DIR}/wasm/vision_wasm_nosimd_internal.js"

echo "  wasm/vision_wasm_nosimd_internal.wasm"
curl -fL --progress-bar "${CDN_BASE}/wasm/vision_wasm_nosimd_internal.wasm" \
  -o "${OUT_DIR}/wasm/vision_wasm_nosimd_internal.wasm"

echo "  models/hand_landmarker.task"
curl -fL --progress-bar "${MODEL_URL}" \
  -o "${OUT_DIR}/models/hand_landmarker.task"

echo ""
echo "Total size: $(du -sh "${OUT_DIR}" | cut -f1)"
echo ""
echo "Done. Pass to GestureInputSource:"
echo "  mediaPipeBaseUrl: '/mediapipe'"
echo "  modelAssetUrl:    '/mediapipe/models/hand_landmarker.task'"
