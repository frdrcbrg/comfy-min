#!/usr/bin/env bash
set -uo pipefail

COMFYUI_DIR="${COMFYUI_DIR:-/opt/ComfyUI}"
LOG=/tmp/comfyui_import_gate.log
rc=0

cd "${COMFYUI_DIR}"
echo "Booting ComfyUI import gate..."
python main.py --cpu --quick-test-for-ci > "${LOG}" 2>&1 || true

echo "----- ComfyUI import log tail -----"
tail -n 80 "${LOG}"
echo "-----------------------------------"

GPU_ONLY_RE="Nvidia_RTX_Nodes_ComfyUI"

if grep -E "IMPORT FAILED" "${LOG}" | grep -vE "${GPU_ONLY_RE}" | grep -q .; then
  echo "ERROR: custom node import failures detected"
  grep -E "IMPORT FAILED" "${LOG}" | grep -vE "${GPU_ONLY_RE}"
  rc=1
fi

while read -r node; do
  case "${node}" in
    ""|\#*) continue ;;
  esac
  if ! grep -q -- "${node}" "${LOG}"; then
    echo "ERROR: expected node not seen in import log: ${node}"
    rc=1
  fi
done < /opt/expected_nodes.txt

if [ "${rc}" -eq 0 ]; then
  echo "ComfyUI import gate OK"
fi

exit "${rc}"
