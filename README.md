# ComfyUI MiniMax H3 Ref2VA / VDN-H3 - Low VRAM 6GB+

<p align="center">
  <img src="https://img.shields.io/badge/ComfyUI-0.36.0-blue?style=for-the-badge" alt="ComfyUI 0.36.0">
  <img src="https://img.shields.io/badge/Model-MiniMax--H3%20Ref2VA-orange?style=for-the-badge" alt="MiniMax-H3 Ref2VA">
  <img src="https://img.shields.io/badge/VRAM-6GB%2B-brightgreen?style=for-the-badge" alt="6GB+ VRAM">
  <img src="https://img.shields.io/badge/VDN--H3-8%20Steps-purple?style=for-the-badge" alt="VDN-H3 8 Steps">
</p>

> **Low-VRAM fork for MiniMax H3 Reference-to-Video.** This repository packages the Ref2VA/VSA node together with the VDN-H3 low-VRAM setup, ComfyUI 0.36 compatibility patch, automatic model installation and ready-to-use workflows.
>
> A **24 GB GPU is not required** for the low-resolution workflows in this fork. We have the pipeline running on **6 GB-class hardware** with aggressive CPU/RAM offloading. More VRAM still allows higher resolution, longer clips and faster execution.

---

## What this fork adds

- MiniMax H3 **Ref2VA** image-to-video / reference-to-video generation.
- **VDN-H3 8-step** inference for better quality than the older 4-step test path.
- Low-VRAM settings for **6 GB+ NVIDIA GPUs**.
- CPU offloading for large model components.
- ComfyUI **0.36.0 attention-shape compatibility fix** for VDN-H3.
- MiniMax block-loop hook installer.
- Optional VSA / 4-step files from the original Ref2VA-VSA project.
- Reference voice support using **MP3 or WAV** files.
- Ready-to-use workflow for image + voice reference generation.
- Complete `install.sh`, `start_lowvram.sh` and `check_install.sh` scripts.

---

## Tested low-VRAM setup

The low-VRAM configuration is intended for systems where the GPU is much smaller than the full MiniMax H3 model.

Typical working settings:

| Setting | Low-VRAM value |
| :--- | :--- |
| GPU VRAM | **6 GB+** |
| System RAM | **32 GB minimum, 64 GB recommended** |
| Resolution | 512x288 or 576x320 |
| Clip length | short clips, typically 73-90 frames |
| FPS | 24 |
| VDN steps | 8 |
| Scheduler | simple |
| Sampler | res_multistep |
| ComfyUI mode | `--lowvram` |
| Text encoder | CPU |
| VDN branch weights | stream |
| VDN retain buffers | off |

The exact maximum resolution and clip length depend on GPU VRAM, system RAM, CUDA/PyTorch version and the selected workflow.

---

## Requirements

- Linux, preferably Ubuntu or Debian.
- NVIDIA GPU with CUDA support.
- **6 GB VRAM or more** for the low-resolution workflows.
- **64 GB system RAM recommended** for comfortable CPU offloading.
- Working NVIDIA driver (`nvidia-smi`).
- Around 50 GB or more free disk space for ComfyUI, checkpoints and caches.

The installer currently uses the tested baseline:

- ComfyUI 0.36.0 baseline
- Python 3.10+
- PyTorch/CUDA packages from the ComfyUI requirements
- VDN-H3 low-VRAM node
- MiniMax-H3-Turbo helper node for pruned-base adapter support

---

## One-command installation

Clone this repository anywhere on the target Linux machine:

```bash
git clone https://github.com/MTSmash-TMP-Networks/ComfyUI-Ref2VA-VSA-6G.git
cd ComfyUI-Ref2VA-VSA-6G
bash install.sh
```

The installer automatically sets up:

```text
System dependencies
    -> ComfyUI
    -> Python virtual environment
    -> TMP Ref2VA/VSA node
    -> VDN-H3 node
    -> MiniMax-H3-Turbo helper node
    -> MiniMax H3 Ref2VA INT8 model
    -> Qwen3-VL text encoder
    -> Video VAE
    -> Audio VAE
    -> optional VSA gate / 4-step LoRA
    -> VDN-H3 stage checkpoint
    -> MiniMax block-loop hook
    -> ComfyUI 0.36 VDN shape patch
    -> example character
    -> test workflow
    -> low-VRAM start script
```

### Start ComfyUI

```bash
~/start_comfyui_vdn_lowvram.sh
```

Default URL:

```text
http://127.0.0.1:8188
```

For LAN access:

```bash
COMFY_LISTEN=0.0.0.0 ~/start_comfyui_vdn_lowvram.sh
```

### Verify the installation

```bash
cd ~/ComfyUI/custom_nodes/ComfyUI-Ref2VA-VSA-6G
bash check_install.sh
```

---

## Installer options

Skip model downloads if the checkpoints already exist:

```bash
SKIP_MODELS=1 bash install.sh
```

Do not install the optional VSA / 4-step model files:

```bash
INSTALL_VSA_FILES=0 bash install.sh
```

Pin an existing ComfyUI installation to the tested baseline:

```bash
PIN_EXISTING_COMFY=1 bash install.sh
```

Install ComfyUI to another directory:

```bash
COMFY_DIR=/opt/ComfyUI bash install.sh
```

---

## Reference image and voice

The included workflow uses:

```text
ComfyUI/input/example_character.jpg
ComfyUI/input/voice_reference.mp3
```

Your own voice reference can be MP3 or WAV. A short, clean speech recording without music or strong room echo generally works best.

Example:

```bash
cp my_voice.mp3 ~/ComfyUI/input/voice_reference.mp3
```

The bundled low-VRAM test workflow is installed to:

```text
ComfyUI/user/default/workflows/TMP-Networks/vdn_h3_audio_reference_576x320_90f.json
```

---

## Checkpoints

The installer downloads the following core models automatically:

| Model Type | File Name | Destination |
| :--- | :--- | :--- |
| Diffusion Model | `minimax_h3_ref2va_pruned_int8_convrot.safetensors` | `models/diffusion_models/` |
| Text Encoder | `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` | `models/text_encoders/` |
| Video VAE | `minimax_h3_video_vae_fp16.safetensors` | `models/vae/` |
| Audio VAE | `minimax_h3_audio_vae_fp32.safetensors` | `models/vae/` |
| VSA Gate | `fasth3_vsa_gate.safetensors` | `models/loras/` |
| Turbo LoRA | `minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors` | `models/loras/` |
| VDN-H3 | `stage-dmd-step-250-int8_convrot_comfyui` | `models/vdn/` |

---

## Low-VRAM VDN configuration

The start script uses conservative settings for small GPUs:

```bash
export VDN_H3_AUTO_MEMORY=0
export VDN_H3_OUTPROJ_CACHE_GIB=0
export VDN_H3_LONG_CACHE_ENABLE=0
export VDN_H3_WINDOW_GROUP_BATCH=1
export VDN_H3_STREAM_PREFETCH=0
export VDN_H3_BRANCH_OVERLAP=0
export VDN_H3_SELECTIVE_WEIGHT_LOAD=1
```

ComfyUI is started with:

```bash
python main.py \
  --listen 127.0.0.1 \
  --port 8188 \
  --lowvram \
  --disable-comfy-compiler
```

These settings intentionally trade speed for lower GPU memory consumption.

---

## ComfyUI 0.36 VDN compatibility patch

Current ComfyUI attention backends may return the dense attention result with the head dimension flattened. Older VDN-H3 code expected a different tensor layout and could fail with an error similar to:

```text
The size of tensor a (1407) must match the size of tensor b (56)
```

This repository includes:

```text
tools/patch_vdn_comfy036.py
```

`install.sh` applies the compatibility patch automatically and creates a backup before changing the VDN file.

---

## About the original 24 GB benchmarks

The upstream Ref2VA-VSA project published its performance comparisons on an RTX 4090 with 24 GB VRAM and high-resolution 1344x768 generation. Those benchmark numbers are useful for comparing inference methods, but **they are not the minimum hardware requirement for this low-VRAM fork**.

This fork focuses on making MiniMax H3 Ref2VA / VDN usable on much smaller GPUs by combining quantized models, CPU offloading, streamed VDN branch weights and lower-resolution workflows.

If you have a 24 GB GPU, you can of course raise resolution and clip length significantly.

---

## Original Ref2VA VSA architecture

[FastVideo](https://github.com/hao-ai-lab/FastVideo) pioneered Visual Sparse Attention (VSA) for text-to-video by clustering video tokens into spatial-temporal tiles and pruning low-value tiles with a learned gate.

The original Ref2VA VSA implementation adapts this to reference-conditioned MiniMax H3 by keeping multimodal reference tokens dense while applying sparse attention to generated video tokens.

The `Ref2VAVSAGatePatch` therefore uses:

1. A dense multimodal prefix for text, reference images and reference audio.
2. Sparse attention only for generated-video tokens.
3. Gate weights transplanted onto the Ref2VA base model.

VDN-H3 is provided as an additional inference path in this fork and is currently the preferred quality-oriented low-VRAM test path.

---

## License and acknowledgements

- Licensed under the [Apache License 2.0](LICENSE).
- Based on the original `ComfyUI-Ref2VA-VSA` work by Kablex.
- VDN-H3 integration uses the `ComfyUI-VDN-H3-24GB` project by Speach1sdef178 with additional low-VRAM configuration and compatibility patching.
- MiniMax-H3-Turbo helper support is based on Larryvrh's ComfyUI node.
- Thanks to the FastVideo, MiniMax, ComfyUI and comfy-kitchen developers.

---

## Disclaimer

This is an experimental low-VRAM setup. Working generation on a 6 GB-class GPU does not mean every resolution, frame count or model combination will fit into 6 GB VRAM. Start with the bundled 512x288 or 576x320 workflows and increase quality gradually.
