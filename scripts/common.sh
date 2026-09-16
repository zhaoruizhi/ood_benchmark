#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config.env}"
if [[ ! -f "$CONFIG_FILE" ]]; then echo "Missing $CONFIG_FILE; cp config.env.example config.env" >&2; exit 2; fi
set -a; source "$CONFIG_FILE"; set +a
export OOD_ROOT MODEL_ID MODEL_DIR GPU_ID HF_HOME HF_DATASETS_CACHE TRANSFORMERS_CACHE ENV_NAME
export CUDA_VISIBLE_DEVICES="$GPU_ID"
mkdir -p "$OOD_ROOT"/logs "$OOD_ROOT"/cache "$OOD_ROOT"/repos "$OOD_ROOT"/results
log(){ echo "[$(date -Is)] $*"; }
venv(){ echo "$OOD_ROOT/venv"; }
activate(){
  if command -v conda >/dev/null 2>&1; then
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate "$ENV_NAME"
  else
    source "$(venv)/bin/activate"
  fi
}
