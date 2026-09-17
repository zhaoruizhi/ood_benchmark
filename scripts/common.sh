#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config.env}"
if [[ ! -f "$CONFIG_FILE" ]]; then echo "Missing $CONFIG_FILE; cp config.env.example config.env" >&2; exit 2; fi
set -a; source "$CONFIG_FILE"; set +a
export OOD_ROOT MODEL_ID MODEL_DIR GPU_ID TP_SIZE HF_HOME HF_DATASETS_CACHE TRANSFORMERS_CACHE ENV_NAME VLLM_USE_V1 NCCL_NVLS_ENABLE BFCL_REV
export CUDA_VISIBLE_DEVICES="$GPU_ID"
mkdir -p "$OOD_ROOT"/logs "$OOD_ROOT"/cache "$OOD_ROOT"/repos "$OOD_ROOT"/results
log(){ echo "[$(date -Is)] $*"; }
env_dir(){ echo "$OOD_ROOT/envs/$1"; }
activate_env(){
  local name="$1"
  local dir
  dir="$(env_dir "$name")"
  if [[ ! -x "$dir/bin/python" ]]; then
    echo "Missing environment $name at $dir; run scripts/01_setup_env.sh" >&2
    exit 2
  fi
  source "$dir/bin/activate"
}
activate_evalplus(){ activate_env evalplus; }
activate_lcb(){ activate_env livecodebench; }
activate_bfcl(){ activate_env bfcl_v3; }
