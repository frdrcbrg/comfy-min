# comfy-min

RunPod-ready ComfyUI Docker image with CUDA, PyTorch, SSH, ComfyUI-Manager, RunpodDirect, Conditioning Krea rebalance, and curated custom nodes.

The image builds ComfyUI from the upstream `Comfy-Org/ComfyUI` repository at build time and keeps models, input, output, and user data on `/workspace` so they can live on a RunPod persistent volume.

## Images

GitHub Actions builds and publishes a `linux/amd64` full image on every push to `main`:

```text
ghcr.io/frdrcbrg/comfy-min:latest
```

The full image is built from [Dockerfile](Dockerfile). It is not based on the slim image; it has its own CUDA devel base, dependency set, ComfyUI install, import gate, and push step.

There is also an experimental smaller image that keeps the old minimal shape:

```text
ghcr.io/frdrcbrg/comfy-min:slim
```

The slim image is built independently from [Dockerfile.slim](Dockerfile.slim) in a separate parallel workflow job. Use `latest` for the full RunPod image and `slim` only if you explicitly want the lightweight variant.

## What's Included

- CUDA 12.8 devel base image
- PyTorch `2.8.0+cu128`
- ComfyUI from `Comfy-Org/ComfyUI`
- ComfyUI-Manager
- ComfyUI-RunpodDirect
- ComfyUI-ConditioningKrea2Rebalance
- RunPod model downloader bridge for ComfyUI's missing-model download buttons
- Civicomfy
- SSH server for RunPod `PUBLIC_KEY` access
- 30 pinned custom-node packs listed in [custom_nodes.txt](custom_nodes.txt)
- FlashAttention and SageAttention best-effort installs, with PyTorch SDPA as fallback
- CI smoke test and ComfyUI import gate before publishing `latest`

No model weights are baked into the image.

## RunPod Pod Template

Use the pushed image as the template container image:

```text
ghcr.io/frdrcbrg/comfy-min:latest
```

Recommended template settings:

- Compute type: NVIDIA GPU
- HTTP ports: `8188/http`
- TCP ports: `22/tcp`
- Network volume mount path: `/workspace`
- Container disk: at least `40 GB`
- Network volume disk: sized for your models

RunPod injects your SSH key via `PUBLIC_KEY` when configured in your RunPod account.

Useful environment variables:

- `COMFYUI_ARGS`: defaults to `--listen 0.0.0.0 --port 8188`
- `WORKSPACE_DIR`: defaults to `/workspace`, the recommended RunPod network volume mount path
- `MODELS_DIR`: defaults to `/workspace/models`; override only if models live on a separately mounted volume
- `REQUIRE_WORKSPACE_MOUNT`: set to `1` to fail startup when `/workspace` is not a mounted volume
- `PUBLIC_KEY`: SSH public key, usually injected by RunPod
- `HF_TOKEN`: optional Hugging Face token for gated model downloads
- `CIVITAI_API_KEY`: optional Civitai token for model downloads

You can also put additional ComfyUI arguments in `/workspace/comfyui_args.txt`, one argument per line:

```text
--preview-method auto
--lowvram
```

## Persistent Layout

These directories are symlinked at startup:

```text
/opt/ComfyUI/models -> ${MODELS_DIR:-/workspace/models}
/opt/ComfyUI/input  -> /workspace/input
/opt/ComfyUI/output -> /workspace/output
/opt/ComfyUI/user   -> /workspace/user
```

On RunPod, attach the network volume with mount path `/workspace`. If `/workspace` is not mounted, the image will still start by default, but the startup log prints a warning because files may be lost with the pod. Set `REQUIRE_WORKSPACE_MOUNT=1` to make that condition fatal.

Put model files under `/workspace/models`, using ComfyUI's normal folder structure:

```text
/workspace/models/checkpoints
/workspace/models/vae
/workspace/models/clip
/workspace/models/unet
/workspace/models/loras
```

## Build Locally

The full image is large and needs substantial Docker disk space:

```bash
docker build --platform linux/amd64 -t ghcr.io/frdrcbrg/comfy-min:latest .
```

To pin a known ComfyUI commit, tag, or branch:

```bash
docker build --build-arg COMFYUI_REF=master -t ghcr.io/frdrcbrg/comfy-min:latest .
```

The slim variant is built separately:

```bash
docker build -f Dockerfile.slim -t ghcr.io/frdrcbrg/comfy-min:slim .
```

## CI Build Flow

The workflow in [.github/workflows/docker-image.yml](.github/workflows/docker-image.yml) can be started manually and also runs automatically when image-relevant files change on `main`. Documentation-only changes do not trigger an image build.

It has two independent jobs:

- `Build, test, and push linux/amd64 image` builds [Dockerfile](Dockerfile), runs the ComfyUI import gate, then publishes `latest` and `sha-<commit>`.
- `Build and push linux/amd64 slim image` builds [Dockerfile.slim](Dockerfile.slim), then publishes `slim` and `slim-sha-<commit>`.

Both jobs use GitHub Actions cache, but neither image inherits from the other.

## Custom Nodes

Custom nodes are pinned in [custom_nodes.txt](custom_nodes.txt) so builds are reproducible. The current full image includes ComfyUI-Manager, RunpodDirect, Civicomfy, the Ultimate-derived node set, and `ComfyUI-ConditioningKrea2Rebalance` pinned to `9ab5315e6aa8`.

## Missing Model Downloads

ComfyUI's Missing Models panel normally starts a browser download when the UI is opened outside Comfy Desktop. This image includes a small local bridge that makes those buttons download into the pod instead. Supported model URLs from Hugging Face, Civitai, and GitHub are downloaded server-side into ComfyUI's registered model directory, for example `/workspace/models/checkpoints`, `/workspace/models/vae`, `/workspace/models/diffusion_models`, or `/workspace/models/text_encoders`. The bridge accepts model files ending in `.safetensors`, `.sft`, `.ckpt`, `.pth`, or `.pt`.

Download progress is shown in a small in-page panel and is also logged periodically in the pod logs.

For gated Hugging Face or Civitai files, set `HF_TOKEN` or `CIVITAI_API_KEY` in the RunPod template.

## Attribution

The custom-node set, pinning strategy, and several dependency-hardening ideas are adapted from [IxMxAMAR/ComfyUI-Ultimate](https://github.com/IxMxAMAR/ComfyUI-Ultimate). The Conditioning Krea rebalance node comes from [nova452/ComfyUI-ConditioningKrea2Rebalance](https://github.com/nova452/ComfyUI-ConditioningKrea2Rebalance).
