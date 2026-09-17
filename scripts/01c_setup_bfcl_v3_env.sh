#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
BFCL_DIR="$OOD_ROOT/repos/gorilla"
if [[ ! -d "$BFCL_DIR/.git" ]]; then
  git clone https://github.com/ShishirPatil/gorilla.git "$BFCL_DIR"
fi
git -C "$BFCL_DIR" switch --detach "$BFCL_REV"
python3 "$ROOT_DIR/scripts/patch_bfcl_v3.py" "$BFCL_DIR/berkeley-function-call-leaderboard"
ENV_DIR="$(env_dir bfcl_v3)"
[[ -x "$ENV_DIR/bin/python" ]] || python3 -m venv "$ENV_DIR"
source "$ENV_DIR/bin/activate"
PIP_OFFLINE=(--no-index --find-links "$OOD_ROOT/cache/wheelhouse")
python -m pip install "${PIP_OFFLINE[@]}" -U pip setuptools wheel
PATCHED_VLLM_WHEEL=$(python "$ROOT_DIR/scripts/patch_evalplus_local_wheel.py" \
  "$OOD_ROOT/cache/wheelhouse/vllm-0.8.5-cp38-abi3-linux_x86_64.whl" \
  "$OOD_ROOT/cache/patched_wheelhouse" --drop opentelemetry-sdk \
  --drop opentelemetry-api --drop opentelemetry-exporter-otlp \
  --drop opentelemetry-semantic-conventions-ai)
python -m pip install "${PIP_OFFLINE[@]}" -U -c "$ROOT_DIR/constraints/bfcl-v3.txt" \
  'torch==2.6.0' 'transformers==4.55.2' 'tokenizers==0.21.4' \
  "$PATCHED_VLLM_WHEEL" 'qwen-agent==0.0.34' soundfile
python -m pip install "${PIP_OFFLINE[@]}" -c "$ROOT_DIR/constraints/bfcl-v3.txt" \
  -e "$BFCL_DIR/berkeley-function-call-leaderboard"
python -m pip check | tee "$OOD_ROOT/logs/bfcl_pip_check.log"
python -m pip freeze | sort > "$OOD_ROOT/logs/bfcl_pip_freeze.txt"
deactivate
