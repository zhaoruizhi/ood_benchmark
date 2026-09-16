#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
{
 date -Is
 nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used,utilization.gpu --format=csv
 python --version 2>/dev/null || true
 python -m pip freeze 2>/dev/null || true
 git -C "$OOD_ROOT/repos/LiveCodeBench" rev-parse HEAD 2>/dev/null || true
 git -C "$OOD_ROOT/repos/gorilla" rev-parse HEAD 2>/dev/null || true
 find "$OOD_ROOT/results" "$OOD_ROOT/logs" -type f -print | sort
} | tee "$OOD_ROOT/experiment_manifest.txt"
