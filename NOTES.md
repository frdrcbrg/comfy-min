# comfy-min Notes

## Current Status

- `ghcr.io/frdrcbrg/comfy-min:latest` is the full RunPod image.
- `ghcr.io/frdrcbrg/comfy-min:slim` is the smaller experimental variant.
- RunPod network volume should be mounted at `/workspace`.
- Startup links persistent directories:
  - `/opt/ComfyUI/models -> ${MODELS_DIR:-/workspace/models}`
  - `/opt/ComfyUI/input -> /workspace/input`
  - `/opt/ComfyUI/output -> /workspace/output`
  - `/opt/ComfyUI/user -> /workspace/user`
- `REQUIRE_WORKSPACE_MOUNT=1` makes startup fail if `/workspace` is not mounted.

## Validated On RunPod

- `/workspace` was detected as a mounted RunPod network volume.
- `ComfyUI-RunpodModelDownloader` loaded as a custom node.
- Missing-model downloads were successfully routed into persistent storage:
  - VAE: `/workspace/models/vae/qwen_image_vae.safetensors`
  - LoRA: `/workspace/models/loras/krea2_darkbrush.safetensors`
  - text encoder: `/workspace/models/text_encoders/qwen3vl_4b_fp8_scaled.safetensors`

## Model Downloader

- The custom bridge exposes `window.__comfyDesktop2.downloadModel(...)` so ComfyUI's existing Missing Models buttons behave like Desktop, but download server-side in the pod.
- Backend route: `POST /runpod-model-downloader/download`
- Status route: `GET /runpod-model-downloader/status/{id}`
- Supported sources: Hugging Face, Civitai, Civitai red, GitHub.
- Supported model extensions: `.safetensors`, `.sft`, `.ckpt`, `.pth`, `.pt`.
- `HF_TOKEN` and `CIVITAI_API_KEY` are used for gated downloads when provided.
- Progress is reported in pod logs and in a small in-page panel.

## Recent Commits

- `cd9f508 Add RunPod missing-model downloader`
- `0a4b5f8 Add RunPod workspace mount guard`
- `3a3b12e Clarify RunPod volume docs`
- `58915e4 Add model download progress reporting`

## Next Ideas

- Watch GitHub Actions run `28190434471` and confirm the image publishes.
- Test the new progress panel on RunPod with a large model download.
- Consider adding cancellation support for active downloads.
- Consider pruning old completed status records from memory after a timeout.
- Consider supporting additional safe model extensions if ComfyUI workflows need them, for example `.gguf`, `.bin`, or `.onnx`.
- Consider fixing the RunPod Tini warning with `tini -s` or `TINI_SUBREAPER=1`.
- Revisit PyTorch/CUDA warning about optimized operations requiring cu130 or higher.
