#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
log "GPU preflight (do not stop other users' processes)"
nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used,utilization.gpu --format=csv
ps -eo pid,user,etime,cmd | grep -E '[v]llm|[t]orchrun|[a]ccelerate|[b]fcl|[l]cb_runner' | head -80 || true
nvidia-smi -i "$GPU_ID" --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv
test -f "$MODEL_DIR/config.json" || { echo "MODEL_DIR missing config.json: $MODEL_DIR" >&2; exit 1; }
test -f "$MODEL_DIR/tokenizer_config.json" || { echo "MODEL_DIR missing tokenizer_config.json" >&2; exit 1; }
mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE" "$TRANSFORMERS_CACHE"
log "model=$MODEL_ID model_dir=$MODEL_DIR gpu=$GPU_ID root=$OOD_ROOT"
