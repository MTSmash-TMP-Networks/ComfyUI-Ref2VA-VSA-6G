# TMP Networks MiniMax H3 / VDN Low-VRAM installation

This repository can bootstrap the Linux setup used for the TMP Networks MiniMax H3 Ref2VA experiments on an NVIDIA laptop GPU.

## Tested baseline

- Linux (Ubuntu/Debian style system)
- NVIDIA RTX 4060 Laptop GPU, 8 GB VRAM
- 64 GB system RAM
- ComfyUI 0.36.0 baseline
- MiniMax H3 Ref2VA pruned INT8 ConvRot
- Qwen3-VL MiniMax H3 NVFP4/AWQ text encoder on CPU
- MiniMax H3 video + audio VAE
- VDN-H3 8-step stage checkpoint
- VDN branch streaming, no retained buffers
- MiniMax-H3 Turbo helper node for pruned-base AdaLN/e-grid support

The setup is intended for 6-8 GB NVIDIA GPUs as an experimental low-VRAM profile. More VRAM allows higher resolution and longer clips.

## One-command installation

```bash
git clone https://github.com/MTSmash-TMP-Networks/ComfyUI-Ref2VA-VSA-6G.git
cd ComfyUI-Ref2VA-VSA-6G
bash install.sh
```

The installer downloads large public model files. Keep at least roughly 50-60 GB of free disk space for a full installation.

## Start

```bash
~/start_comfyui_vdn_lowvram.sh
```

By default ComfyUI only listens locally on `127.0.0.1:8188`.

For LAN access:

```bash
COMFY_LISTEN=0.0.0.0 ~/start_comfyui_vdn_lowvram.sh
```

## Voice reference

The public repository intentionally does not contain a private voice sample. Put your own file into:

```text
~/ComfyUI/input/voice_reference.mp3
```

MP3 and WAV can be used by ComfyUI's audio loader. For the cleanest reference, use a short voice-only recording without music or strong reverb.

## Installer options

```bash
# Re-use already downloaded/shared models
SKIP_MODELS=1 bash install.sh

# Install VDN but skip the old VSA gate and 4-step LoRA downloads
INSTALL_VSA_FILES=0 bash install.sh

# Force an existing ComfyUI checkout onto the tested 0.36.0 commit
PIN_EXISTING_COMFY=1 bash install.sh

# Install ComfyUI somewhere else
COMFY_DIR=/opt/ComfyUI bash install.sh

# Skip apt package installation
INSTALL_SYSTEM_DEPS=0 bash install.sh
```

## What the installer changes

The script installs or configures:

- ComfyUI (fresh installs are pinned to the tested 0.36.0 commit)
- Python virtual environment under `ComfyUI/.venv`
- this repository as a custom node
- `Speach1sdef178/ComfyUI-VDN-H3-24GB` at the tested revision
- `Larryvrh/ComfyUI-MiniMax-H3-Turbo` at the tested revision
- MiniMax H3 model, text encoder and both VAEs
- optional VSA gate and legacy 4-step Ref2V LoRA
- VDN-H3 INT8 ConvRot stage checkpoint
- the VDN MiniMax block-loop hook
- the ComfyUI 0.36 attention-shape compatibility patch used by this low-VRAM setup
- a low-VRAM start script
- the example reference image and a test workflow

The installer never downloads or publishes a personal voice reference.

## Model locations

```text
ComfyUI/models/diffusion_models/
  minimax_h3_ref2va_pruned_int8_convrot.safetensors

ComfyUI/models/text_encoders/
  qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors

ComfyUI/models/vae/
  minimax_h3_video_vae_fp16.safetensors
  minimax_h3_audio_vae_fp32.safetensors

ComfyUI/models/loras/
  fasth3_vsa_gate.safetensors
  minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors

ComfyUI/models/vdn/stage-dmd-step-250-int8_convrot_comfyui/
  model_spec.json
  linear_branch/
  adapters/default/
  adapters/turbo/
```

## Low-VRAM VDN profile

The start script exports:

```text
VDN_H3_AUTO_MEMORY=0
VDN_H3_OUTPROJ_CACHE_GIB=0
VDN_H3_LONG_CACHE_ENABLE=0
VDN_H3_WINDOW_GROUP_BATCH=1
VDN_H3_STREAM_PREFETCH=0
VDN_H3_BRANCH_OVERLAP=0
VDN_H3_SELECTIVE_WEIGHT_LOAD=1
```

This avoids the node's 24 GB AutoMemory calibration and reduces extra GPU caching. It does not guarantee that every resolution or frame count fits on a 6-8 GB GPU.

## Recommended first test

Use the included VDN audio-reference workflow at 576x320. Copy `voice_reference.mp3` into the input directory before loading the workflow.

If VRAM is exhausted, lower resolution or frame count first. If there is headroom, increase resolution in small steps.

## Upstream licenses

The installer pulls code and model assets from several upstream projects. Review the upstream licenses and model terms before redistribution or commercial deployment.
