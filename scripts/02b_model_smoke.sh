#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; activate_evalplus
MODEL_DIR="$MODEL_DIR" TP_SIZE="$TP_SIZE" python "$ROOT_DIR/scripts/vllm_smoke.py" \
  2>&1 | tee "$OOD_ROOT/logs/vllm_smoke.log"
deactivate
