#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
{
 date -Is
 nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used,utilization.gpu --format=csv
 for env in evalplus livecodebench bfcl_v3; do
   py="$OOD_ROOT/envs/$env/bin/python"
   if [[ -x "$py" ]]; then
     echo "[$env]"
     "$py" --version
     "$py" -m pip freeze | sort
   fi
 done
 git -C "$OOD_ROOT/repos/LiveCodeBench" rev-parse HEAD 2>/dev/null || true
 git -C "$OOD_ROOT/repos/gorilla" rev-parse HEAD 2>/dev/null || true
 find "$OOD_ROOT/results" "$OOD_ROOT/logs" -type f -print | sort
} | tee "$OOD_ROOT/experiment_manifest.txt"
