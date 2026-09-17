#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
ENV_DIR="$(env_dir evalplus)"
[[ -x "$ENV_DIR/bin/python" ]] || python3 -m venv "$ENV_DIR"
source "$ENV_DIR/bin/activate"
PIP_OFFLINE=(--no-index --find-links "$OOD_ROOT/cache/wheelhouse")
python -m pip install "${PIP_OFFLINE[@]}" -U pip setuptools wheel
PATCHED_WHEEL_DIR="$OOD_ROOT/cache/patched_wheelhouse"
PATCHED_EVALPLUS_WHEEL=$(python "$ROOT_DIR/scripts/patch_evalplus_local_wheel.py" \
  "$OOD_ROOT/cache/wheelhouse/evalplus-0.3.1-py3-none-any.whl" "$PATCHED_WHEEL_DIR" \
  --drop google-generativeai)
PATCHED_VLLM_WHEEL=$(python "$ROOT_DIR/scripts/patch_evalplus_local_wheel.py" \
  "$OOD_ROOT/cache/wheelhouse/vllm-0.8.5-cp38-abi3-linux_x86_64.whl" "$PATCHED_WHEEL_DIR" \
  --drop opentelemetry-sdk --drop opentelemetry-api \
  --drop opentelemetry-exporter-otlp --drop opentelemetry-semantic-conventions-ai)
python -m pip install "${PIP_OFFLINE[@]}" -U -c "$ROOT_DIR/constraints/evalplus.txt" \
  'torch==2.6.0' 'transformers==4.55.2' 'tokenizers==0.21.4' \
  'tree-sitter==0.25.0' 'tree-sitter-python==0.25.0' \
  accelerate safetensors 'datasets==3.6.0' "$PATCHED_VLLM_WHEEL" "$PATCHED_EVALPLUS_WHEEL"
python -c 'from tree_sitter import Language, Parser; import tree_sitter_python; Parser(Language(tree_sitter_python.language())); print("tree-sitter parser compatibility: OK")'
python -m pip check | tee "$OOD_ROOT/logs/evalplus_pip_check.log"
python -m pip freeze | sort > "$OOD_ROOT/logs/evalplus_pip_freeze.txt"
deactivate
