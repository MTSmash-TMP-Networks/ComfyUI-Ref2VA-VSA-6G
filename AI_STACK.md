# TMP Media AI Stack

This layer turns ComfyUI into a multi-GPU media backend for EVA.

## Included capabilities

- FLUX.1 Schnell text-to-image
- LTX-2.5 text/image-to-video support through current ComfyUI core + LTXVideo add-on
- MiniMax H3 Ref2VA + VDN-H3 talking/reference video
- TTS Audio Suite for speech, voice cloning, audio tools and multiple TTS engines
- Video Helper Suite, KJNodes, GGUF and ComfyUI Manager
- FastAPI gateway for templates and arbitrary ComfyUI API workflows
- Multi-GPU scheduling across multiple local ComfyUI workers
- `/object_info` exposure so EVA can inspect installed node types and later construct workflows dynamically

## Install

Ubuntu/Debian with working NVIDIA driver:

```bash
sudo -E MODEL_PROFILE=all GPU_IDS=1,2,3 bash install_ai_stack.sh
```

For LTX-2.5, accept the model terms on Hugging Face first and pass a read token:

```bash
sudo -E HF_TOKEN=hf_xxx MODEL_PROFILE=all GPU_IDS=1,2,3 bash install_ai_stack.sh
```

If the server has fewer GPUs and `GPU_IDS` is omitted, all detected GPUs are used. If 4+ GPUs are detected, the installer defaults to GPUs `1,2,3` so GPU 0 can remain reserved for EVA.

## API

The gateway defaults to port `8200`. Swagger/OpenAPI is available at `/docs`.

Core endpoints:

- `GET /api/v1/health`
- `GET /api/v1/workers`
- `GET /api/v1/templates`
- `GET /api/v1/nodes`
- `POST /api/v1/assets`
- `POST /api/v1/workflows/validate`
- `POST /api/v1/jobs`
- `POST /api/v1/jobs/raw`
- `GET /api/v1/jobs/{job_id}`
- `GET /api/v1/jobs/{job_id}/outputs`

All endpoints use `X-API-Key` when `TMP_MEDIA_API_KEY` is configured.

## AI-ready workflow model

EVA can use two modes:

1. **Template mode**: select a known template and fill parameters.
2. **Raw workflow mode**: query `/api/v1/nodes`, build a ComfyUI API-format workflow, validate it, then submit it to `/api/v1/jobs/raw`.

This allows reliable production templates today and agent-built workflows later.

## Models

`ai_stack/scripts/download_models.sh` supports:

```bash
download_models.sh flux
download_models.sh ltx
download_models.sh h3
download_models.sh all
```

LTX-2.5 is gated on Hugging Face and requires accepting its terms. The installer uses the ComfyUI INT8/ConvRot transformer and text encoder plus video/audio VAEs and the x2 latent spatial upscaler.

## Multi-GPU

Each GPU gets an independent ComfyUI process. All workers share model and input folders but use separate output/temp/user directories. The gateway polls `/queue` and sends a new job to the least-busy reachable worker.

Example with GPU 0 reserved for EVA:

```text
GPU 0 -> EVA LLM
GPU 1 -> ComfyUI worker :8189
GPU 2 -> ComfyUI worker :8190
GPU 3 -> ComfyUI worker :8191
Gateway -> :8200
```

## TTS

TTS Audio Suite is installed as the audio layer. Individual engines/models may be downloaded on first use depending on the selected TTS engine. This avoids downloading every available speech model during the initial install.

## Social content path

A later EVA content workflow can be expressed as:

```text
brief -> script -> scenes -> FLUX / LTX-2.5 / H3 -> TTS -> upscale -> compose -> social draft/publish API
```

The publishing connector is intentionally not enabled in this first stack. The renderer/gateway is prepared so publishing can be added without changing the rendering API.
