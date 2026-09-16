#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; activate
LCB_DIR="$OOD_ROOT/repos/LiveCodeBench"
if [[ ! -d "$LCB_DIR/.git" ]]; then git clone https://github.com/LiveCodeBench/LiveCodeBench.git "$LCB_DIR"; fi
cd "$LCB_DIR"; git rev-parse HEAD | tee "$OOD_ROOT/logs/livecodebench_commit.log"
python -m pip install -e .
python -m pip check | tee "$OOD_ROOT/logs/lcb_pip_check.log"
python - <<'PY'
from pathlib import Path
p=Path('lcb_runner/lm_styles.py'); s=p.read_text(); needle='LanguageModelStore: dict[str, LanguageModel] = {'
entry='''    LanguageModel(\n        "Qwen/Qwen3-4B-Instruct-2507", "Qwen3-4B-Instruct-2507",\n        LMStyle.CodeQwenInstruct, datetime(2025, 7, 1),\n        link="https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507",\n    ),\n'''
if '"Qwen/Qwen3-4B-Instruct-2507"' not in s: p.write_text(s.replace(needle,entry+needle))
PY
python - <<'PY'
from lcb_runner.lm_styles import LanguageModelStore
assert 'Qwen/Qwen3-4B-Instruct-2507' in LanguageModelStore
PY
python -m lcb_runner.runner.main --model "$MODEL_ID" --local_model_path "$MODEL_DIR" --scenario codegeneration --release_version "$LCB_RELEASE" --tensor_parallel_size "$TP_SIZE" --not_fast --use_cache --evaluate 2>&1 | tee "$OOD_ROOT/logs/lcb_${LCB_RELEASE}.log"
mkdir -p "$OOD_ROOT/results/lcb_${LCB_RELEASE}"; cp -a output/. "$OOD_ROOT/results/lcb_${LCB_RELEASE}/"
deactivate
