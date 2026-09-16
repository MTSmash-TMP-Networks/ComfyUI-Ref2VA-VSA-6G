#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo; echo "ERROR at line $LINENO. Installation stopped." >&2' ERR

# -----------------------------------------------------------------------------
# TMP Networks - MiniMax H3 Ref2VA / VDN low-VRAM installer
# Tested baseline: ComfyUI 0.36.0, Linux, NVIDIA RTX 4060 Laptop 8 GB, 64 GB RAM.
# -----------------------------------------------------------------------------

SELF_REPO_URL="${SELF_REPO_URL:-https://github.com/MTSmash-TMP-Networks/ComfyUI-Ref2VA-VSA-6G.git}"
COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
COMFY_REF="${COMFY_REF:-7a0b5eede3f9721c8faab290689893f36edc6d66}"
VDN_REF="${VDN_REF:-fe3370851f08c556280a6a0afe4273de618df717}"
TURBO_REF="${TURBO_REF:-4274783a23afcfdbea3b4876cb79effd6c510785}"

INSTALL_SYSTEM_DEPS="${INSTALL_SYSTEM_DEPS:-1}"
PIN_EXISTING_COMFY="${PIN_EXISTING_COMFY:-0}"
SKIP_MODELS="${SKIP_MODELS:-0}"
INSTALL_VSA_FILES="${INSTALL_VSA_FILES:-1}"
INSTALL_VDN="${INSTALL_VDN:-1}"

VDN_REPO_URL="https://github.com/Speach1sdef178/ComfyUI-VDN-H3-24GB.git"
TURBO_REPO_URL="https://github.com/Larryvrh/ComfyUI-MiniMax-H3-Turbo.git"
VDN_HF_REPO="speach1sdef178/VDN-H3-INT8-ConvRot-ComfyUI"
VDN_NAME="stage-dmd-step-250-int8_convrot_comfyui"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
NODE_DIR="$COMFY_DIR/custom_nodes/ComfyUI-Ref2VA-VSA-6G"
VDN_NODE_DIR="$COMFY_DIR/custom_nodes/ComfyUI-VDN-H3-24GB"
TURBO_NODE_DIR="$COMFY_DIR/custom_nodes/ComfyUI-MiniMax-H3-Turbo"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        fail "Root privileges are required for system packages. Install sudo or run with INSTALL_SYSTEM_DEPS=0."
    fi
}

clone_pinned() {
    local url="$1" target="$2" ref="$3"
    if [ -d "$target/.git" ]; then
        git -C "$target" fetch --quiet origin
    else
        rm -rf "$target"
        git clone "$url" "$target"
    fi
    git -C "$target" checkout --quiet --detach "$ref"
}

download_file() {
    local url="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ -s "$dest" ]; then
        echo "OK exists: $dest"
        return 0
    fi
    local part="${dest}.part"
    echo "Downloading: $(basename "$dest")"
    if ! curl -L --fail --retry 5 --retry-delay 3 -C - -o "$part" "$url"; then
        warn "Resume failed for $(basename "$dest"); restarting this file."
        rm -f "$part"
        curl -L --fail --retry 5 --retry-delay 3 -o "$part" "$url"
    fi
    mv "$part" "$dest"
}

say "Pre-flight checks"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || true
else
    warn "nvidia-smi was not found. Install a working NVIDIA driver before rendering."
fi

if command -v free >/dev/null 2>&1; then
    ram_gib=$(free -g | awk '/^Mem:/ {print $2}')
    echo "System RAM: ${ram_gib:-unknown} GiB"
    if [ -n "${ram_gib:-}" ] && [ "$ram_gib" -lt 32 ]; then
        warn "Less than 32 GiB RAM detected. The Qwen text encoder and CPU offload can be difficult."
    fi
fi

free_kb=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
if [ -n "${free_kb:-}" ] && [ "$free_kb" -lt 52428800 ]; then
    warn "Less than about 50 GiB free disk space detected. A full model install may not fit."
fi

if [ "$INSTALL_SYSTEM_DEPS" = "1" ] && command -v apt-get >/dev/null 2>&1; then
    say "Installing Ubuntu/Debian packages"
    as_root apt-get update
    as_root apt-get install -y \
        ca-certificates git curl wget ffmpeg \
        python3 python3-venv python3-pip build-essential \
        libgl1 libglib2.0-0
else
    say "Skipping system packages"
fi

command -v git >/dev/null 2>&1 || fail "git is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

say "Installing ComfyUI"
if [ ! -d "$COMFY_DIR/.git" ]; then
    rm -rf "$COMFY_DIR"
    git clone https://github.com/Comfy-Org/ComfyUI.git "$COMFY_DIR"
    git -C "$COMFY_DIR" checkout --quiet --detach "$COMFY_REF"
    echo "Pinned fresh ComfyUI install to $COMFY_REF (0.36.0 baseline)."
else
    echo "Existing ComfyUI detected: $COMFY_DIR"
    if [ "$PIN_EXISTING_COMFY" = "1" ]; then
        git -C "$COMFY_DIR" fetch --quiet origin
        git -C "$COMFY_DIR" checkout --quiet --detach "$COMFY_REF"
        echo "Existing ComfyUI pinned to $COMFY_REF."
    else
        echo "Leaving the existing ComfyUI revision unchanged."
    fi
fi

say "Creating Python environment"
if [ ! -f "$COMFY_DIR/.venv/bin/activate" ]; then
    python3 -m venv "$COMFY_DIR/.venv"
fi
# shellcheck disable=SC1091
source "$COMFY_DIR/.venv/bin/activate"
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r "$COMFY_DIR/requirements.txt"
python -m pip install --upgrade huggingface_hub safetensors

say "Installing this TMP Networks Ref2VA/VSA repository"
mkdir -p "$COMFY_DIR/custom_nodes"
if [ "$(realpath -m "$SCRIPT_DIR")" = "$(realpath -m "$NODE_DIR")" ]; then
    echo "Repository already runs from the ComfyUI custom_nodes directory."
elif [ -d "$NODE_DIR/.git" ]; then
    if ! git -C "$NODE_DIR" pull --ff-only; then
        warn "Could not fast-forward the existing TMP node checkout; keeping its current files."
    fi
else
    rm -rf "$NODE_DIR"
    git clone "$SELF_REPO_URL" "$NODE_DIR"
fi
python -m pip install -r "$NODE_DIR/requirements.txt"

say "Installing VDN-H3 and MiniMax-H3 Turbo helper node"
clone_pinned "$VDN_REPO_URL" "$VDN_NODE_DIR" "$VDN_REF"
clone_pinned "$TURBO_REPO_URL" "$TURBO_NODE_DIR" "$TURBO_REF"

if [ -f "$TURBO_NODE_DIR/requirements.txt" ]; then
    python -m pip install -r "$TURBO_NODE_DIR/requirements.txt"
fi
if [ -f "$VDN_NODE_DIR/requirements.txt" ]; then
    python -m pip install -r "$VDN_NODE_DIR/requirements.txt"
fi

if [ "$SKIP_MODELS" != "1" ]; then
    say "Downloading MiniMax H3 base models"
    download_file \
      "https://huggingface.co/Comfy-Org/MiniMax_H3_repackaged/resolve/main/split_files/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" \
      "$COMFY_DIR/models/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"

    download_file \
      "https://huggingface.co/Comfy-Org/MiniMax_H3_repackaged/resolve/main/split_files/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
      "$COMFY_DIR/models/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"

    download_file \
      "https://huggingface.co/Comfy-Org/MiniMax_H3_repackaged/resolve/main/split_files/vae/minimax_h3_video_vae_fp16.safetensors" \
      "$COMFY_DIR/models/vae/minimax_h3_video_vae_fp16.safetensors"

    download_file \
      "https://huggingface.co/Comfy-Org/MiniMax_H3_repackaged/resolve/main/split_files/vae/minimax_h3_audio_vae_fp32.safetensors" \
      "$COMFY_DIR/models/vae/minimax_h3_audio_vae_fp32.safetensors"

    if [ "$INSTALL_VSA_FILES" = "1" ]; then
        say "Downloading optional VSA / 4-step files"
        download_file \
          "https://huggingface.co/barelymining/ComfyUI-MiniMax-H3-FastVideo/resolve/main/fasth3_vsa_gate.safetensors" \
          "$COMFY_DIR/models/loras/fasth3_vsa_gate.safetensors"

        download_file \
          "https://huggingface.co/lightx2v/Minimax-h3-Turbo/resolve/main/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors" \
          "$COMFY_DIR/models/loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors"
    fi

    if [ "$INSTALL_VDN" = "1" ]; then
        say "Downloading VDN-H3 8-step stage checkpoint"
        mkdir -p "$COMFY_DIR/models/vdn"
        hf download "$VDN_HF_REPO" \
            --include "$VDN_NAME/*" \
            --local-dir "$COMFY_DIR/models/vdn"
    fi
else
    say "SKIP_MODELS=1: model downloads skipped"
fi

if [ "$INSTALL_VDN" = "1" ]; then
    say "Installing MiniMax block-loop hook required by the VDN node"
    python "$VDN_NODE_DIR/tools/install_minimax_block_loop_hook.py" --comfy-ui "$COMFY_DIR"

    say "Applying ComfyUI 0.36 attention-shape compatibility patch"
    python "$NODE_DIR/tools/patch_vdn_comfy036.py" --comfy-ui "$COMFY_DIR"
fi

say "Installing sample input and workflow"
mkdir -p "$COMFY_DIR/input"
if [ -f "$NODE_DIR/example_character.jpg" ]; then
    cp -f "$NODE_DIR/example_character.jpg" "$COMFY_DIR/input/example_character.jpg"
elif [ -f "$NODE_DIR/assets/example_character.jpg" ]; then
    cp -f "$NODE_DIR/assets/example_character.jpg" "$COMFY_DIR/input/example_character.jpg"
fi

mkdir -p "$COMFY_DIR/user/default/workflows/TMP-Networks"
if [ -f "$NODE_DIR/workflows/vdn_h3_audio_reference_576x320_90f.json" ]; then
    cp -f "$NODE_DIR/workflows/vdn_h3_audio_reference_576x320_90f.json" \
        "$COMFY_DIR/user/default/workflows/TMP-Networks/"
fi

install -m 0755 "$NODE_DIR/start_lowvram.sh" "$HOME/start_comfyui_vdn_lowvram.sh"

say "Verification"
python - <<'PY'
import torch
print("PyTorch:", torch.__version__)
print("CUDA runtime:", torch.version.cuda)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    props = torch.cuda.get_device_properties(0)
    print("GPU:", torch.cuda.get_device_name(0))
    print("VRAM:", round(props.total_memory / 1024**3, 2), "GiB")
PY

required=(
  "$COMFY_DIR/models/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
  "$COMFY_DIR/models/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
  "$COMFY_DIR/models/vae/minimax_h3_video_vae_fp16.safetensors"
  "$COMFY_DIR/models/vae/minimax_h3_audio_vae_fp32.safetensors"
)
if [ "$SKIP_MODELS" != "1" ]; then
    for f in "${required[@]}"; do
        [ -s "$f" ] || fail "Required file missing after install: $f"
    done
fi

if [ "$INSTALL_VDN" = "1" ] && [ "$SKIP_MODELS" != "1" ]; then
    required_vdn=(
      "$COMFY_DIR/models/vdn/$VDN_NAME/model_spec.json"
      "$COMFY_DIR/models/vdn/$VDN_NAME/linear_branch/model_int8_convrot_comfyui.safetensors"
      "$COMFY_DIR/models/vdn/$VDN_NAME/adapters/default/adapter_model.safetensors"
      "$COMFY_DIR/models/vdn/$VDN_NAME/adapters/turbo/adapter_model.safetensors"
    )
    for f in "${required_vdn[@]}"; do
        [ -s "$f" ] || fail "VDN checkpoint incomplete: $f"
    done
fi

cat <<EOF

====================================================================
Installation complete.

Start ComfyUI:
  ~/start_comfyui_vdn_lowvram.sh

Local URL:
  http://127.0.0.1:8188

For LAN access:
  COMFY_LISTEN=0.0.0.0 ~/start_comfyui_vdn_lowvram.sh

Voice reference:
  Copy your own MP3 or WAV to:
  $COMFY_DIR/input/voice_reference.mp3

Test workflow:
  $COMFY_DIR/user/default/workflows/TMP-Networks/vdn_h3_audio_reference_576x320_90f.json

Useful installer options:
  SKIP_MODELS=1 ./install.sh
  INSTALL_VSA_FILES=0 ./install.sh
  PIN_EXISTING_COMFY=1 ./install.sh
  COMFY_DIR=/opt/ComfyUI ./install.sh
====================================================================
EOF