#!/usr/bin/env bash
set -Eeuo pipefail

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
VDN_NAME="stage-dmd-step-250-int8_convrot_comfyui"

ok=0
bad=0

check_file() {
    local f="$1"
    if [ -s "$f" ]; then
        printf 'OK    %s\n' "$f"
        ok=$((ok + 1))
    else
        printf 'MISS  %s\n' "$f"
        bad=$((bad + 1))
    fi
}

check_dir() {
    local d="$1"
    if [ -d "$d" ]; then
        printf 'OK    %s/\n' "$d"
        ok=$((ok + 1))
    else
        printf 'MISS  %s/\n' "$d"
        bad=$((bad + 1))
    fi
}

echo "TMP Networks ComfyUI low-VRAM installation check"
echo "ComfyUI: $COMFY_DIR"
echo

check_file "$COMFY_DIR/main.py"
check_file "$COMFY_DIR/.venv/bin/python"
check_dir "$COMFY_DIR/custom_nodes/ComfyUI-Ref2VA-VSA-6G"
check_dir "$COMFY_DIR/custom_nodes/ComfyUI-VDN-H3-24GB"
check_dir "$COMFY_DIR/custom_nodes/ComfyUI-MiniMax-H3-Turbo"

check_file "$COMFY_DIR/models/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
check_file "$COMFY_DIR/models/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
check_file "$COMFY_DIR/models/vae/minimax_h3_video_vae_fp16.safetensors"
check_file "$COMFY_DIR/models/vae/minimax_h3_audio_vae_fp32.safetensors"

check_file "$COMFY_DIR/models/vdn/$VDN_NAME/model_spec.json"
check_file "$COMFY_DIR/models/vdn/$VDN_NAME/linear_branch/model_int8_convrot_comfyui.safetensors"
check_file "$COMFY_DIR/models/vdn/$VDN_NAME/adapters/default/adapter_model.safetensors"
check_file "$COMFY_DIR/models/vdn/$VDN_NAME/adapters/turbo/adapter_model.safetensors"

check_file "$COMFY_DIR/input/example_character.jpg"

if command -v nvidia-smi >/dev/null 2>&1; then
    echo
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || true
else
    echo
    echo "WARN  nvidia-smi not found"
fi

if [ -x "$COMFY_DIR/.venv/bin/python" ]; then
    echo
    "$COMFY_DIR/.venv/bin/python" - <<'PY' || true
import torch
print("PyTorch:", torch.__version__)
print("CUDA runtime:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
PY
fi

echo
echo "Result: $ok OK, $bad missing"

if [ "$bad" -ne 0 ]; then
    exit 1
fi
