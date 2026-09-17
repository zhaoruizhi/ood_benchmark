#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
LCB_DIR="$OOD_ROOT/repos/LiveCodeBench"
if [[ ! -d "$LCB_DIR/.git" ]]; then
  git clone https://github.com/LiveCodeBench/LiveCodeBench.git "$LCB_DIR"
fi
python "$ROOT_DIR/scripts/patch_livecodebench.py" "$LCB_DIR/lcb_runner/lm_styles.py"
ENV_DIR="$(env_dir livecodebench)"
[[ -x "$ENV_DIR/bin/python" ]] || python3 -m venv "$ENV_DIR"
source "$ENV_DIR/bin/activate"
PIP_OFFLINE=(--no-index --find-links "$OOD_ROOT/cache/wheelhouse")
python -m pip install "${PIP_OFFLINE[@]}" -U pip setuptools wheel
python -m pip install "${PIP_OFFLINE[@]}" -U -c "$ROOT_DIR/constraints/livecodebench.txt" \
  'torch==2.6.0' 'transformers==4.55.2' 'tokenizers==0.21.4' 'vllm==0.8.5'
python -m pip install "${PIP_OFFLINE[@]}" -c "$ROOT_DIR/constraints/livecodebench.txt" -e "$LCB_DIR"
python -m py_compile "$LCB_DIR/lcb_runner/lm_styles.py"
python -m pip check | tee "$OOD_ROOT/logs/lcb_pip_check.log"
python -m pip freeze | sort > "$OOD_ROOT/logs/lcb_pip_freeze.txt"
deactivate
