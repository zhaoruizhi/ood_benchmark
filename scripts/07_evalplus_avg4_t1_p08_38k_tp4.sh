#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config.env}"
source "$ROOT_DIR/scripts/common.sh"

if [[ "$TP_SIZE" != "4" ]]; then
  echo "This preset requires TP_SIZE=4, got TP_SIZE=$TP_SIZE in $CONFIG_FILE" >&2
  exit 2
fi

IFS=',' read -r -a selected_gpus <<< "$GPU_ID"
if (( ${#selected_gpus[@]} != 4 )); then
  echo "This preset requires four GPUs, got GPU_ID=$GPU_ID in $CONFIG_FILE" >&2
  exit 2
fi

export AVG4_SEEDS="${AVG4_SEEDS:-20260917,20260918,20260919,20260920}"
export AVG4_TEMPERATURE=1.0
export AVG4_TOP_P=0.8
export AVG4_TOP_K=-1
export AVG4_MAX_NEW_TOKENS=38912
export AVG4_MAX_MODEL_LEN=40960
export AVG_ROOT="${AVG_ROOT:-$OOD_ROOT/results/evalplus_avg4_t1_p08_k-1_new38912_ctx40960_tp4}"

exec bash "$ROOT_DIR/scripts/06_evalplus_avg4.sh"
