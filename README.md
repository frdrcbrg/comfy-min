# comfy-min

Minimal ComfyUI Docker image for Runpod Pods.

The image builds ComfyUI from the upstream `Comfy-Org/ComfyUI` repository at build time and keeps models, input, output, and user data on `/workspace` so they can live on a Runpod persistent volume.

## Image

GitHub Actions builds and publishes a `linux/amd64` image on every push to `main`:

```text
ghcr.io/frdrcbrg/comfy-min:latest
```

Use that image directly in a Runpod Pod template.

## Build

```bash
docker build -t ghcr.io/frdrcbrg/comfy-min:latest .
```

For Runpod, build and push an `amd64` image:

```bash
docker build --platform linux/amd64 -t ghcr.io/frdrcbrg/comfy-min:latest .
docker push ghcr.io/frdrcbrg/comfy-min:latest
```

There is also an experimental slim Dockerfile that starts from plain Ubuntu instead of an NVIDIA CUDA runtime image. It still installs PyTorch CUDA wheels, but avoids carrying the base CUDA runtime layer:

```bash
docker build -f Dockerfile.slim -t ghcr.io/frdrcbrg/comfy-min:slim .
```

To pin a known ComfyUI commit, tag, or branch:

```bash
docker build --build-arg COMFYUI_REF=master -t ghcr.io/frdrcbrg/comfy-min:latest .
```

## Run Locally

```bash
docker run --rm -it \
  --gpus all \
  -p 8188:8188 \
  -v "$PWD/workspace:/workspace" \
  ghcr.io/frdrcbrg/comfy-min:latest
```

Open `http://localhost:8188`.

## Runpod Pod Template

Use the pushed image as the template container image.

- Compute type: NVIDIA GPU
- HTTP ports: `8188/http`
- Volume mount path: `/workspace`
- Container disk: at least `20 GB`
- Volume disk: sized for your models

Leave the container start command empty unless you want to override `COMFYUI_ARGS`.

Useful environment variables:

- `COMFYUI_ARGS`: defaults to `--listen 0.0.0.0 --port 8188`
- `WORKSPACE_DIR`: defaults to `/workspace`

You can also put additional ComfyUI arguments in `/workspace/comfyui_args.txt`, one argument per line:

```text
--max-batch-size 8
--preview-method auto
```

## Model Layout

Put model files under `/workspace/models`, using ComfyUI's normal folder structure, for example:

```text
/workspace/models/checkpoints
/workspace/models/vae
/workspace/models/clip
/workspace/models/unet
/workspace/models/loras
```
