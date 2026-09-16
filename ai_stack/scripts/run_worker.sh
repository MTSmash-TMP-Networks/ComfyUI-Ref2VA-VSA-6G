#!/usr/bin/env bash
set -Eeuo pipefail

GPU_ID="${1:?GPU id required}"
ROOT="${TMP_MEDIA_ROOT:-/opt/tmp-media-ai}"
COMFY="$ROOT/ComfyUI"
BASE_PORT="${TMP_COMFY_BASE_PORT:-8188}"
LISTEN="${TMP_COMFY_LISTEN:-127.0.0.1}"
PORT=$((BASE_PORT + GPU_ID))

export CUDA_VISIBLE_DEVICES="$GPU_ID"
export VDN_H3_AUTO_MEMORY="${VDN_H3_AUTO_MEMORY:-0}"
export VDN_H3_OUTPROJ_CACHE_GIB="${VDN_H3_OUTPROJ_CACHE_GIB:-0}"
export VDN_H3_LONG_CACHE_ENABLE="${VDN_H3_LONG_CACHE_ENABLE:-0}"
export VDN_H3_WINDOW_GROUP_BATCH="${VDN_H3_WINDOW_GROUP_BATCH:-1}"
export VDN_H3_STREAM_PREFETCH="${VDN_H3_STREAM_PREFETCH:-0}"
export VDN_H3_BRANCH_OVERLAP="${VDN_H3_BRANCH_OVERLAP:-0}"
export VDN_H3_SELECTIVE_WEIGHT_LOAD="${VDN_H3_SELECTIVE_WEIGHT_LOAD:-1}"

mkdir -p "$ROOT/output/gpu${GPU_ID}" "$ROOT/temp/gpu${GPU_ID}" "$ROOT/user/gpu${GPU_ID}"
cd "$COMFY"
source "$COMFY/.venv/bin/activate"

exec python main.py \
  --listen "$LISTEN" \
  --port "$PORT" \
  --lowvram \
  --disable-comfy-compiler \
  --output-directory "$ROOT/output/gpu${GPU_ID}" \
  --temp-directory "$ROOT/temp/gpu${GPU_ID}" \
  --user-directory "$ROOT/user/gpu${GPU_ID}"
