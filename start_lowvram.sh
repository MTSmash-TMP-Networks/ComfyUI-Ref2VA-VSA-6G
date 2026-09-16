#!/usr/bin/env bash
set -Eeuo pipefail

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
LISTEN_HOST="${COMFY_LISTEN:-127.0.0.1}"
PORT="${COMFY_PORT:-8188}"

if [ ! -f "$COMFY_DIR/main.py" ]; then
    echo "ERROR: ComfyUI not found at $COMFY_DIR"
    exit 1
fi
if [ ! -f "$COMFY_DIR/.venv/bin/activate" ]; then
    echo "ERROR: Python venv not found at $COMFY_DIR/.venv"
    exit 1
fi

cd "$COMFY_DIR"
source "$COMFY_DIR/.venv/bin/activate"

# Low-VRAM profile used by the TMP Networks test setup (RTX 4060 Laptop 8 GB).
# It is also a reasonable starting point for 6-8 GB NVIDIA GPUs.
export VDN_H3_AUTO_MEMORY=0
export VDN_H3_OUTPROJ_CACHE_GIB=0
export VDN_H3_LONG_CACHE_ENABLE=0
export VDN_H3_WINDOW_GROUP_BATCH=1
export VDN_H3_STREAM_PREFETCH=0
export VDN_H3_BRANCH_OVERLAP=0
export VDN_H3_SELECTIVE_WEIGHT_LOAD=1

python - <<'PY'
import torch
print("PyTorch:", torch.__version__)
print("CUDA runtime:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    p = torch.cuda.get_device_properties(0)
    print("GPU:", torch.cuda.get_device_name(0))
    print("VRAM:", round(p.total_memory / 1024**3, 2), "GiB")
PY

echo "ComfyUI: http://${LISTEN_HOST}:${PORT}"

exec python main.py \
    --listen "$LISTEN_HOST" \
    --port "$PORT" \
    --lowvram \
    --disable-comfy-compiler