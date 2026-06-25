FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04

ARG COMFYUI_REF=master
ARG PYTORCH_CUDA=cu128
ARG TORCH_VERSION=2.8.0
ARG TORCHVISION_VERSION=0.23.0
ARG TORCHAUDIO_VERSION=2.8.0

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/bin:/usr/bin:/bin \
    PIP_CONSTRAINT=/opt/constraints.txt \
    UV_CONSTRAINT=/opt/constraints.txt \
    COMFYUI_DIR=/opt/ComfyUI \
    COMFYUI_ARGS="--listen 0.0.0.0 --port 8188" \
    WORKSPACE_DIR=/workspace \
    HF_HUB_DISABLE_TELEMETRY=1 \
    WAS_BLOCK_AUTO_INSTALL=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 \
    build-essential \
    ca-certificates \
    curl \
    ffmpeg \
    git \
    git-lfs \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    libsndfile1 \
    ninja-build \
    openssh-server \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    tini \
    wget \
    && git lfs install \
    && ssh-keygen -A \
    && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && rm -rf /var/lib/apt/lists/*

COPY constraints.txt /opt/constraints.txt

RUN python3 -m venv /opt/venv \
    && python -m pip install --upgrade pip setuptools wheel uv \
    && pip install \
        "torch==${TORCH_VERSION}+${PYTORCH_CUDA}" \
        "torchvision==${TORCHVISION_VERSION}+${PYTORCH_CUDA}" \
        "torchaudio==${TORCHAUDIO_VERSION}+${PYTORCH_CUDA}" \
        --index-url "https://download.pytorch.org/whl/${PYTORCH_CUDA}" \
    && python -c "import torch; assert '+${PYTORCH_CUDA}' in torch.__version__, torch.__version__; print('torch', torch.__version__, 'cuda', torch.version.cuda)"

COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

RUN uv pip install --no-cache \
    numpy numba llvmlite \
    transformers tokenizers huggingface-hub diffusers accelerate peft safetensors \
    protobuf mediapipe pillow scipy scikit-image scikit-learn \
    kornia timm sentencepiece einops matplotlib simpleeval \
    open-clip-torch clip-interrogator gguf ultralytics spandrel \
    onnx

RUN pip install --no-cache-dir \
      "https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.3.post1/flash_attn-2.8.3.post1%2Bcu12torch2.8cxx11abiTRUE-cp312-cp312-linux_x86_64.whl" \
    || pip install flash-attn==2.8.3.post1 --no-build-isolation \
    || echo "WARN: flash-attn install failed; continuing with PyTorch SDPA"

RUN bash -c '\
  try_sage() { pip uninstall -y sageattention >/dev/null 2>&1 || true; \
               pip install --no-cache-dir --no-deps --force-reinstall "$1" \
               && python /opt/scripts/check_sageattention.py; }; \
  if try_sage "https://huggingface.co/Kijai/PrecompiledWheels/resolve/main/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl"; then \
    echo "SageAttention prebuilt wheel installed"; \
  elif try_sage "https://github.com/thekie/sageattention-wheel/releases/download/2.2.0.post1/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl"; then \
    echo "SageAttention fallback wheel installed"; \
  else \
    echo "WARN: SageAttention install failed; continuing with PyTorch SDPA"; \
    pip uninstall -y sageattention >/dev/null 2>&1 || true; \
  fi'

RUN git clone --depth 1 --branch "${COMFYUI_REF}" https://github.com/Comfy-Org/ComfyUI.git "${COMFYUI_DIR}"
WORKDIR ${COMFYUI_DIR}
RUN uv pip install --no-cache -r requirements.txt

COPY custom_nodes.txt /opt/custom_nodes.txt
COPY expected_nodes.txt /opt/expected_nodes.txt
RUN /opt/scripts/install_custom_nodes.sh /opt/custom_nodes.txt

RUN pip uninstall -y opencv-python opencv-python-headless opencv-contrib-python opencv-contrib-python-headless onnxruntime onnxruntime-gpu || true \
    && uv pip install --no-cache opencv-contrib-python-headless==4.11.0.86 onnxruntime-gpu==1.22.0

RUN python /opt/scripts/smoke_test.py

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8188 22

ENTRYPOINT ["/usr/bin/tini", "--", "/start.sh"]
CMD []
