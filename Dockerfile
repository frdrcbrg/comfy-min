FROM nvidia/cuda:13.0.2-runtime-ubuntu24.04

ARG COMFYUI_REF=master
ARG PYTORCH_CUDA=cu130

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    COMFYUI_DIR=/opt/ComfyUI \
    COMFYUI_ARGS="--listen 0.0.0.0 --port 8188"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    libgl1 \
    libglib2.0-0 \
    python3 \
    python3-pip \
    python3-venv \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${COMFYUI_REF}" https://github.com/Comfy-Org/ComfyUI.git "${COMFYUI_DIR}"

WORKDIR ${COMFYUI_DIR}

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip setuptools wheel \
    && /opt/venv/bin/pip install torch torchvision torchaudio --index-url "https://download.pytorch.org/whl/${PYTORCH_CUDA}" \
    && /opt/venv/bin/pip install -r requirements.txt

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8188

ENTRYPOINT ["/usr/bin/tini", "--", "/start.sh"]
CMD []
