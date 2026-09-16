#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${TMP_MEDIA_ROOT:-/opt/tmp-media-ai}"
COMFY="$ROOT/ComfyUI"
PROFILE="${1:-all}"
HF="${COMFY}/.venv/bin/hf"

[ -x "$HF" ] || { echo "hf CLI not found: $HF" >&2; exit 1; }
mkdir -p "$COMFY/models"/{checkpoints,diffusion_models,text_encoders,vae,loras,latent_upscale_models,vdn}

hf_download() {
  local repo="$1" file="$2" dest_root="$3"
  if [ -n "${HF_TOKEN:-}" ]; then
    "$HF" download "$repo" "$file" --token "$HF_TOKEN" --local-dir "$dest_root"
  else
    "$HF" download "$repo" "$file" --local-dir "$dest_root"
  fi
}

install_flux() {
  echo "==> FLUX.1-schnell FP8"
  hf_download "Comfy-Org/flux1-schnell" "flux1-schnell-fp8.safetensors" "$COMFY/models/checkpoints"
}

install_ltx() {
  echo "==> LTX-2.5 ComfyUI INT8 pack"
  echo "NOTE: LTX-2.5 is gated. Accept its Hugging Face terms and set HF_TOKEN if needed."
  hf_download "Lightricks/LTX-2.5" "diffusion_models/ltx-2.5-22b-distilled-transformer-comfy-int8-convrot.safetensors" "$COMFY/models"
  hf_download "Lightricks/LTX-2.5" "text_encoders/gemma4-12b-with-proj-ltx-2.5-comfy-int8-convrot.safetensors" "$COMFY/models"
  hf_download "Lightricks/LTX-2.5" "vae/ltx-2.5-video-vae-bf16.safetensors" "$COMFY/models"
  hf_download "Lightricks/LTX-2.5" "vae/ltx-2.5-audio-vae-bf16.safetensors" "$COMFY/models"
  hf_download "Lightricks/LTX-2.5" "latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors" "$COMFY/models"
}

install_h3() {
  echo "==> MiniMax H3 Ref2VA / VDN"
  hf_download "Comfy-Org/MiniMax_H3_repackaged" "split_files/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" "$ROOT/hf_h3"
  hf_download "Comfy-Org/MiniMax_H3_repackaged" "split_files/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" "$ROOT/hf_h3"
  hf_download "Comfy-Org/MiniMax_H3_repackaged" "split_files/vae/minimax_h3_video_vae_fp16.safetensors" "$ROOT/hf_h3"
  hf_download "Comfy-Org/MiniMax_H3_repackaged" "split_files/vae/minimax_h3_audio_vae_fp32.safetensors" "$ROOT/hf_h3"
  cp -f "$ROOT/hf_h3/split_files/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" "$COMFY/models/diffusion_models/"
  cp -f "$ROOT/hf_h3/split_files/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" "$COMFY/models/text_encoders/"
  cp -f "$ROOT/hf_h3/split_files/vae/minimax_h3_video_vae_fp16.safetensors" "$COMFY/models/vae/"
  cp -f "$ROOT/hf_h3/split_files/vae/minimax_h3_audio_vae_fp32.safetensors" "$COMFY/models/vae/"
  rm -rf "$ROOT/hf_h3"

  hf_download "speach1sdef178/VDN-H3-INT8-ConvRot-ComfyUI" "stage-dmd-step-250-int8_convrot_comfyui/model_spec.json" "$COMFY/models/vdn"
  hf_download "speach1sdef178/VDN-H3-INT8-ConvRot-ComfyUI" "stage-dmd-step-250-int8_convrot_comfyui/linear_branch/model_int8_convrot_comfyui.safetensors" "$COMFY/models/vdn"
  hf_download "speach1sdef178/VDN-H3-INT8-ConvRot-ComfyUI" "stage-dmd-step-250-int8_convrot_comfyui/adapters/default/adapter_config.json" "$COMFY/models/vdn"
  hf_download "speach1sdef178/VDN-H3-INT8-ConvRot-ComfyUI" "stage-dmd-step-250-int8_convrot_comfyui/adapters/default/adapter_model.safetensors" "$COMFY/models/vdn"
  hf_download "speach1sdef178/VDN-H3-INT8-ConvRot-ComfyUI" "stage-dmd-step-250-int8_convrot_comfyui/adapters/turbo/adapter_config.json" "$COMFY/models/vdn"
  hf_download "speach1sdef178/VDN-H3-INT8-ConvRot-ComfyUI" "stage-dmd-step-250-int8_convrot_comfyui/adapters/turbo/adapter_model.safetensors" "$COMFY/models/vdn"
}

case "$PROFILE" in
  flux) install_flux ;;
  ltx) install_ltx ;;
  h3) install_h3 ;;
  all)
    rc=0
    install_flux || rc=1
    install_ltx || rc=1
    install_h3 || rc=1
    exit "$rc"
    ;;
  none) echo "No models requested." ;;
  *) echo "Usage: $0 {flux|ltx|h3|all|none}" >&2; exit 2 ;;
esac
