#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
bash "$ROOT_DIR/scripts/00_preflight.sh"
if [[ -x "$OOD_ROOT/envs/evalplus/bin/python" ]]; then
  source "$OOD_ROOT/envs/evalplus/bin/activate"
elif [[ -x "$OOD_ROOT/venv/bin/python" ]]; then
  source "$OOD_ROOT/venv/bin/activate"
else
  activate_evalplus
fi
MODEL_DIR="$MODEL_DIR" TP_SIZE="$TP_SIZE" python "$ROOT_DIR/scripts/vllm_smoke.py" \
  2>&1 | tee "$OOD_ROOT/logs/vllm_smoke.log"
deactivate
