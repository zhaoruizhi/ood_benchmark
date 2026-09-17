#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
log "GPU preflight (do not stop other users' processes)"
nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used,utilization.gpu --format=csv
ps -eo pid,user,etime,cmd | grep -E '[v]llm|[t]orchrun|[a]ccelerate|[b]fcl|[l]cb_runner' | head -80 || true
nvidia-smi -i "$GPU_ID" --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv

if [[ ! "$TP_SIZE" =~ ^[1-9][0-9]*$ ]]; then
  echo "TP_SIZE must be a positive integer, got: $TP_SIZE" >&2
  exit 2
fi

IFS=',' read -r -a SELECTED_GPUS <<< "$GPU_ID"
if (( ${#SELECTED_GPUS[@]} != TP_SIZE )); then
  echo "GPU_ID selects ${#SELECTED_GPUS[@]} GPU(s), but TP_SIZE=$TP_SIZE; refusing to launch." >&2
  exit 2
fi

GPU_BUSY_THRESHOLD_MIB="${GPU_BUSY_THRESHOLD_MIB:-1024}"
if [[ ! "$GPU_BUSY_THRESHOLD_MIB" =~ ^[0-9]+$ ]]; then
  echo "GPU_BUSY_THRESHOLD_MIB must be a non-negative integer, got: $GPU_BUSY_THRESHOLD_MIB" >&2
  exit 2
fi

GPU_BUSY=0
for raw_gpu in "${SELECTED_GPUS[@]}"; do
  gpu="${raw_gpu//[[:space:]]/}"
  if [[ ! "$gpu" =~ ^[0-9]+$ ]]; then
    echo "Invalid GPU index in GPU_ID: $raw_gpu" >&2
    exit 2
  fi
  used_mib="$(nvidia-smi -i "$gpu" --query-gpu=memory.used --format=csv,noheader,nounits | tr -d ' ')"
  if [[ ! "$used_mib" =~ ^[0-9]+$ ]]; then
    echo "Could not read memory usage for GPU $gpu: $used_mib" >&2
    exit 2
  fi
  if (( used_mib > GPU_BUSY_THRESHOLD_MIB )); then
    echo "GPU $gpu is busy (${used_mib} MiB used); refusing to launch a benchmark." >&2
    GPU_BUSY=1
  fi
done
if (( GPU_BUSY )); then
  exit 3
fi
test -f "$MODEL_DIR/config.json" || { echo "MODEL_DIR missing config.json: $MODEL_DIR" >&2; exit 1; }
test -f "$MODEL_DIR/tokenizer_config.json" || { echo "MODEL_DIR missing tokenizer_config.json" >&2; exit 1; }
mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE" "$TRANSFORMERS_CACHE"
log "model=$MODEL_ID model_dir=$MODEL_DIR gpu=$GPU_ID root=$OOD_ROOT"
