#!/usr/bin/env bash
set -euo pipefail

COMFYUI_DIR="${COMFYUI_DIR:-/opt/ComfyUI}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
DEFAULT_COMFYUI_ARGS="--listen 0.0.0.0 --port 8188"

mkdir -p \
  "${WORKSPACE_DIR}/models" \
  "${WORKSPACE_DIR}/input" \
  "${WORKSPACE_DIR}/output" \
  "${WORKSPACE_DIR}/user"

link_workspace_dir() {
  local name="$1"
  local target="${COMFYUI_DIR}/${name}"
  if [ -e "${target}" ] && [ ! -L "${target}" ]; then
    rm -rf "${target}"
  fi
  ln -sfnT "${WORKSPACE_DIR}/${name}" "${target}"
}

link_workspace_dir models
link_workspace_dir input
link_workspace_dir output
link_workspace_dir user

ARGS_FILE="${WORKSPACE_DIR}/comfyui_args.txt"
if [ -s "${ARGS_FILE}" ]; then
  EXTRA_ARGS="$(grep -v '^[[:space:]]*#' "${ARGS_FILE}" | tr '\n' ' ')"
  if [ -n "${EXTRA_ARGS//[[:space:]]/}" ]; then
    COMFYUI_ARGS="${COMFYUI_ARGS:-${DEFAULT_COMFYUI_ARGS}} ${EXTRA_ARGS}"
  fi
fi

cd "${COMFYUI_DIR}"
exec /opt/venv/bin/python main.py ${COMFYUI_ARGS:-${DEFAULT_COMFYUI_ARGS}} "$@"
