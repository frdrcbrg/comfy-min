#!/usr/bin/env bash
set -euo pipefail

COMFYUI_DIR="${COMFYUI_DIR:-/opt/ComfyUI}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
MODELS_DIR="${MODELS_DIR:-${WORKSPACE_DIR}/models}"
DEFAULT_COMFYUI_ARGS="--listen 0.0.0.0 --port 8188"

mkdir -p \
  "${MODELS_DIR}" \
  "${WORKSPACE_DIR}/input" \
  "${WORKSPACE_DIR}/output" \
  "${WORKSPACE_DIR}/user"

if mountpoint -q "${WORKSPACE_DIR}"; then
  echo "[start] workspace mount detected at ${WORKSPACE_DIR}"
else
  echo "[start] WARN: ${WORKSPACE_DIR} is not a mountpoint; data may be stored on ephemeral pod/container storage"
  if [ "${REQUIRE_WORKSPACE_MOUNT:-0}" = "1" ]; then
    echo "[start] ERROR: REQUIRE_WORKSPACE_MOUNT=1 but ${WORKSPACE_DIR} is not mounted"
    exit 1
  fi
fi

df -h "${WORKSPACE_DIR}" || true

link_persistent_dir() {
  local name="$1"
  local source="$2"
  local target="${COMFYUI_DIR}/${name}"

  if [ -d "${target}" ] && [ ! -L "${target}" ]; then
    cp -an "${target}/." "${source}/" 2>/dev/null || true
    rm -rf "${target}"
  elif [ -e "${target}" ] && [ ! -L "${target}" ]; then
    rm -rf "${target}"
  fi

  ln -sfnT "${source}" "${target}"
  echo "[start] ${target} -> ${source}"
}

link_persistent_dir models "${MODELS_DIR}"
link_persistent_dir input "${WORKSPACE_DIR}/input"
link_persistent_dir output "${WORKSPACE_DIR}/output"
link_persistent_dir user "${WORKSPACE_DIR}/user"

if [ -n "${PUBLIC_KEY:-}" ]; then
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  printf '%s\n' "${PUBLIC_KEY}" >> /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

mkdir -p /run/sshd
/usr/sbin/sshd && echo "[start] sshd up on :22" || echo "[start] WARN: sshd failed"

ARGS_FILE="${WORKSPACE_DIR}/comfyui_args.txt"
if [ -s "${ARGS_FILE}" ]; then
  EXTRA_ARGS="$(grep -v '^[[:space:]]*#' "${ARGS_FILE}" | tr '\n' ' ')"
  if [ -n "${EXTRA_ARGS//[[:space:]]/}" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS:-${DEFAULT_COMFYUI_ARGS}} ${EXTRA_ARGS}"
  fi
fi

cd "${COMFYUI_DIR}"
echo "[start] launching ComfyUI on :8188"
exec /opt/venv/bin/python main.py ${COMFYUI_ARGS:-${DEFAULT_COMFYUI_ARGS}} "$@"
