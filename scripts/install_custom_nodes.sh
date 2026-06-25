#!/usr/bin/env bash
set -uo pipefail

PINS="${1:-/opt/custom_nodes.txt}"
COMFYUI_DIR="${COMFYUI_DIR:-/opt/ComfyUI}"
NODES_DIR="${COMFYUI_DIR}/custom_nodes"
PIP_INSTALL="uv pip install --no-cache"

mkdir -p "${NODES_DIR}"
fail=0

install_requirements() {
  local dir="$1"
  if [ -f "${dir}/requirements.txt" ]; then
    echo "Installing requirements for ${dir}"
    ${PIP_INSTALL} -r "${dir}/requirements.txt" || {
      echo "WARN: requirements failed for ${dir}"
      fail=1
    }
  fi
}

while read -r name url sha; do
  case "${name}" in
    ""|\#*) continue ;;
  esac

  dest="${NODES_DIR}/${name}"
  echo "=== ${name} @ ${sha} ==="

  if [ ! -d "${dest}/.git" ]; then
    git clone --filter=blob:none "${url}" "${dest}" || {
      echo "ERROR: clone failed for ${name}"
      fail=1
      continue
    }
  fi

  git -C "${dest}" checkout -q "${sha}" || {
    echo "ERROR: checkout failed for ${name} (${sha})"
    fail=1
    continue
  }

  case "${name}" in
    ComfyUI-Frame-Interpolation)
      if [ -f "${dest}/requirements-no-cupy.txt" ]; then
        ${PIP_INSTALL} -r "${dest}/requirements-no-cupy.txt" || fail=1
      else
        install_requirements "${dest}"
      fi
      ${PIP_INSTALL} cupy-cuda12x || echo "WARN: cupy-cuda12x install failed"
      ;;
    ComfyUI-Impact-Pack)
      export SAM2_BUILD_CUDA=0
      install_requirements "${dest}"
      ;;
    Nvidia_RTX_Nodes_ComfyUI)
      pip install --no-cache-dir nvidia-vfx --extra-index-url https://pypi.nvidia.com/ \
        || echo "WARN: nvidia-vfx install failed; RTX nodes may be unavailable"
      ;;
    *)
      install_requirements "${dest}"
      ;;
  esac
done < "${PINS}"

if [ "${fail}" -ne 0 ]; then
  echo "WARN: one or more custom-node install steps failed; the CI import gate will decide if this image is usable"
fi

exit 0
