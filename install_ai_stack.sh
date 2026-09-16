#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO" >&2' ERR

ROOT="${TMP_MEDIA_ROOT:-/opt/tmp-media-ai}"
REPO_URL="${TMP_MEDIA_REPO:-https://github.com/MTSmash-TMP-Networks/ComfyUI-Ref2VA-VSA-6G.git}"
COMFY_REF="${COMFY_REF:-7a0b5eede3f9721c8faab290689893f36edc6d66}"
MODEL_PROFILE="${MODEL_PROFILE:-all}"
INSTALL_MODELS="${INSTALL_MODELS:-1}"
GATEWAY_PORT="${TMP_MEDIA_GATEWAY_PORT:-8200}"
BASE_PORT="${TMP_COMFY_BASE_PORT:-8188}"

say(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn(){ printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2; }
need_root(){ [ "$(id -u)" -eq 0 ] || { echo "Run this installer as root (sudo)." >&2; exit 1; }; }
clone_or_update(){
  local url="$1" dst="$2" ref="${3:-}"
  if [ -d "$dst/.git" ]; then
    git -C "$dst" fetch --all --tags --prune
  else
    rm -rf "$dst"
    git clone "$url" "$dst"
  fi
  if [ -n "$ref" ]; then
    git -C "$dst" checkout --detach "$ref"
  else
    git -C "$dst" checkout "$(git -C "$dst" remote show origin | awk '/HEAD branch/ {print $NF}')" || true
    git -C "$dst" pull --ff-only || true
  fi
}
install_node_deps(){
  local dir="$1"
  [ -f "$dir/requirements.txt" ] && "$ROOT/ComfyUI/.venv/bin/python" -m pip install -r "$dir/requirements.txt"
}

need_root
say "Installing system packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git curl wget jq ffmpeg python3 python3-venv python3-pip build-essential \
  libgl1 libglib2.0-0 libsndfile1 sox aria2 ca-certificates

mkdir -p "$ROOT"
if ! id tmpmedia >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /var/lib/tmp-media --shell /usr/sbin/nologin tmpmedia
fi

say "Installing source bundle"
if [ -d "$ROOT/source/.git" ]; then
  git -C "$ROOT/source" fetch origin
  git -C "$ROOT/source" pull --ff-only || true
else
  git clone "$REPO_URL" "$ROOT/source"
fi
rm -rf "$ROOT/ai_stack"
cp -a "$ROOT/source/ai_stack" "$ROOT/ai_stack"

say "Installing ComfyUI pinned baseline"
clone_or_update "https://github.com/Comfy-Org/ComfyUI.git" "$ROOT/ComfyUI" "$COMFY_REF"
python3 -m venv "$ROOT/ComfyUI/.venv"
"$ROOT/ComfyUI/.venv/bin/python" -m pip install --upgrade pip setuptools wheel
"$ROOT/ComfyUI/.venv/bin/python" -m pip install -r "$ROOT/ComfyUI/requirements.txt"
"$ROOT/ComfyUI/.venv/bin/python" -m pip install --upgrade huggingface_hub safetensors

say "Installing ComfyUI add-ons"
NODES="$ROOT/ComfyUI/custom_nodes"
mkdir -p "$NODES"
clone_or_update "$REPO_URL" "$NODES/ComfyUI-Ref2VA-VSA-6G"
clone_or_update "https://github.com/Speach1sdef178/ComfyUI-VDN-H3-24GB.git" "$NODES/ComfyUI-VDN-H3-24GB" "fe3370851f08c556280a6a0afe4273de618df717"
clone_or_update "https://github.com/Larryvrh/ComfyUI-MiniMax-H3-Turbo.git" "$NODES/ComfyUI-MiniMax-H3-Turbo" "4274783a23afcfdbea3b4876cb79effd6c510785"
clone_or_update "https://github.com/Comfy-Org/ComfyUI-Manager.git" "$NODES/ComfyUI-Manager"
clone_or_update "https://github.com/Lightricks/ComfyUI-LTXVideo.git" "$NODES/ComfyUI-LTXVideo"
clone_or_update "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "$NODES/ComfyUI-VideoHelperSuite"
clone_or_update "https://github.com/kijai/ComfyUI-KJNodes.git" "$NODES/ComfyUI-KJNodes"
clone_or_update "https://github.com/city96/ComfyUI-GGUF.git" "$NODES/ComfyUI-GGUF"
clone_or_update "https://github.com/diodiogod/TTS-Audio-Suite.git" "$NODES/TTS-Audio-Suite"

for d in \
  "$NODES/ComfyUI-Ref2VA-VSA-6G" \
  "$NODES/ComfyUI-VDN-H3-24GB" \
  "$NODES/ComfyUI-MiniMax-H3-Turbo" \
  "$NODES/ComfyUI-Manager" \
  "$NODES/ComfyUI-LTXVideo" \
  "$NODES/ComfyUI-VideoHelperSuite" \
  "$NODES/ComfyUI-KJNodes" \
  "$NODES/ComfyUI-GGUF"; do
  install_node_deps "$d"
done

say "Installing TTS Audio Suite dependencies"
if [ -f "$NODES/TTS-Audio-Suite/install.py" ]; then
  (cd "$NODES/TTS-Audio-Suite" && "$ROOT/ComfyUI/.venv/bin/python" install.py)
else
  install_node_deps "$NODES/TTS-Audio-Suite"
fi

say "Applying VDN hooks / compatibility patch"
"$ROOT/ComfyUI/.venv/bin/python" "$NODES/ComfyUI-VDN-H3-24GB/tools/install_minimax_block_loop_hook.py" --comfy-ui "$ROOT/ComfyUI"
"$ROOT/ComfyUI/.venv/bin/python" "$NODES/ComfyUI-Ref2VA-VSA-6G/tools/patch_vdn_comfy036.py" --comfy-ui "$ROOT/ComfyUI"

say "Installing TMP Media Gateway"
python3 -m venv "$ROOT/gateway-venv"
"$ROOT/gateway-venv/bin/python" -m pip install --upgrade pip wheel
"$ROOT/gateway-venv/bin/python" -m pip install -r "$ROOT/ai_stack/requirements.txt"
mkdir -p "$ROOT/state" "$ROOT/output" "$ROOT/temp" "$ROOT/user" "$ROOT/ComfyUI/input"

say "Detecting GPUs"
GPU_COUNT=$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | wc -l | tr -d ' ' || true)
[ "${GPU_COUNT:-0}" -gt 0 ] || { echo "No NVIDIA GPU detected by nvidia-smi." >&2; exit 1; }
if [ -n "${GPU_IDS:-}" ]; then
  IDS="$GPU_IDS"
elif [ "$GPU_COUNT" -ge 4 ]; then
  IDS="1,2,3"
  warn "4+ GPUs detected. Defaulting to GPU_IDS=1,2,3 so GPU 0 can remain reserved for EVA. Override with GPU_IDS=..."
else
  IDS=$(seq -s, 0 $((GPU_COUNT-1)))
fi
IFS=',' read -r -a GPU_ARRAY <<< "$IDS"

WORKERS=()
for id in "${GPU_ARRAY[@]}"; do
  id="$(echo "$id" | xargs)"
  [ -n "$id" ] || continue
  WORKERS+=("http://127.0.0.1:$((BASE_PORT + id))")
done
WORKER_CSV=$(IFS=,; echo "${WORKERS[*]}")

if [ -z "${TMP_MEDIA_API_KEY:-}" ]; then
  TMP_MEDIA_API_KEY=$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)
fi

cat > /etc/tmp-media-ai.env <<EOF2
TMP_MEDIA_ROOT=$ROOT
TMP_MEDIA_GATEWAY_PORT=$GATEWAY_PORT
TMP_COMFY_BASE_PORT=$BASE_PORT
TMP_COMFY_LISTEN=127.0.0.1
TMP_MEDIA_WORKERS=$WORKER_CSV
TMP_MEDIA_API_KEY=$TMP_MEDIA_API_KEY
TMP_MEDIA_INPUT_DIR=$ROOT/ComfyUI/input
TMP_MEDIA_TEMPLATE_DIR=$ROOT/ai_stack/templates
TMP_MEDIA_DB=$ROOT/state/jobs.sqlite3
EOF2
chmod 600 /etc/tmp-media-ai.env

say "Installing systemd services"
cp -f "$ROOT/ai_stack/systemd/tmp-comfy@.service" /etc/systemd/system/tmp-comfy@.service
cp -f "$ROOT/ai_stack/systemd/tmp-media-gateway.service" /etc/systemd/system/tmp-media-gateway.service
systemctl daemon-reload
for id in "${GPU_ARRAY[@]}"; do
  id="$(echo "$id" | xargs)"
  systemctl enable "tmp-comfy@${id}.service"
done
systemctl enable tmp-media-gateway.service

if [ "$INSTALL_MODELS" = "1" ]; then
  say "Downloading model profile: $MODEL_PROFILE"
  if ! HF_TOKEN="${HF_TOKEN:-}" TMP_MEDIA_ROOT="$ROOT" "$ROOT/ai_stack/scripts/download_models.sh" "$MODEL_PROFILE"; then
    warn "One or more model downloads failed. LTX-2.5 is gated and may require accepting the model terms plus HF_TOKEN. Add-ons and services are installed; rerun download_models.sh after authentication."
  fi
else
  warn "INSTALL_MODELS=0: skipping model downloads"
fi

say "Copying test assets / official UI workflows"
if [ -f "$NODES/ComfyUI-Ref2VA-VSA-6G/example_character.jpg" ]; then
  cp -f "$NODES/ComfyUI-Ref2VA-VSA-6G/example_character.jpg" "$ROOT/ComfyUI/input/example_character.jpg"
fi
mkdir -p "$ROOT/ComfyUI/user/default/workflows/TMP-Networks"
curl -fsSL "https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates/flux_schnell.json" \
  -o "$ROOT/ComfyUI/user/default/workflows/TMP-Networks/flux_schnell_ui.json" || true
curl -fsSL "https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/templates/video_ltx2_5_t2v.json" \
  -o "$ROOT/ComfyUI/user/default/workflows/TMP-Networks/ltx2_5_t2v_ui.json" || true

say "Fixing service ownership"
chown -R tmpmedia:tmpmedia "$ROOT" /var/lib/tmp-media

say "Starting workers and gateway"
for id in "${GPU_ARRAY[@]}"; do
  id="$(echo "$id" | xargs)"
  systemctl restart "tmp-comfy@${id}.service"
done
systemctl restart tmp-media-gateway.service

sleep 5

echo
cat <<EOF2
====================================================================
TMP Media AI stack installed.

Root:       $ROOT
Gateway:    http://SERVER-IP:$GATEWAY_PORT
API docs:   http://SERVER-IP:$GATEWAY_PORT/docs
GPU IDs:    $IDS
Workers:    $WORKER_CSV

API key (save this):
$TMP_MEDIA_API_KEY

Health check:
  source /etc/tmp-media-ai.env
  $ROOT/ai_stack/scripts/healthcheck.sh

FLUX test:
  curl -X POST http://127.0.0.1:$GATEWAY_PORT/api/v1/jobs \
    -H "X-API-Key: $TMP_MEDIA_API_KEY" \
    -H 'Content-Type: application/json' \
    -d '{"template_id":"flux_schnell","parameters":{"prompt":"A professional TMP Networks homelab rack, cinematic product photography","width":1024,"height":1024}}'

Models can be installed/retried later:
  source /etc/tmp-media-ai.env
  HF_TOKEN=hf_xxx $ROOT/ai_stack/scripts/download_models.sh ltx
  $ROOT/ai_stack/scripts/download_models.sh flux
  $ROOT/ai_stack/scripts/download_models.sh h3

EVA tool schema:
  $ROOT/ai_stack/eva_tool_schema.json
====================================================================
EOF2
