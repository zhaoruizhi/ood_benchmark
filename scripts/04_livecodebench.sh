#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; activate_lcb
LCB_DIR="$OOD_ROOT/repos/LiveCodeBench"
if [[ ! -d "$LCB_DIR/.git" ]]; then git clone https://github.com/LiveCodeBench/LiveCodeBench.git "$LCB_DIR"; fi
cd "$LCB_DIR"; git rev-parse HEAD | tee "$OOD_ROOT/logs/livecodebench_commit.log"
python "$ROOT_DIR/scripts/patch_livecodebench.py" "$LCB_DIR/lcb_runner/lm_styles.py"
python -m py_compile "$LCB_DIR/lcb_runner/lm_styles.py"
python - <<'PY'
from lcb_runner.lm_styles import LanguageModelStore
assert 'Qwen/Qwen3-4B-Instruct-2507' in LanguageModelStore
PY
python -m lcb_runner.runner.main --model "$MODEL_ID" --local_model_path "$MODEL_DIR" --scenario codegeneration --release_version "$LCB_RELEASE" --tensor_parallel_size "$TP_SIZE" --n 10 --temperature 0.2 --top_p 0.95 --not_fast --use_cache --evaluate 2>&1 | tee "$OOD_ROOT/logs/lcb_${LCB_RELEASE}.log"
mkdir -p "$OOD_ROOT/results/lcb_${LCB_RELEASE}"; cp -a output/. "$OOD_ROOT/results/lcb_${LCB_RELEASE}/"
deactivate
