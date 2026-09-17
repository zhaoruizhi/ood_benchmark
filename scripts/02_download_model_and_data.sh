#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
activate_evalplus
python -m pip install -U huggingface_hub
if [[ ! -f "$MODEL_DIR/config.json" ]]; then
  mkdir -p "$MODEL_DIR"
  hf download "$MODEL_ID" --local-dir "$MODEL_DIR" 2>&1 | tee "$OOD_ROOT/logs/model_download.log"
fi
MODEL_DIR="$MODEL_DIR" python - <<'PY'
import os, json
from pathlib import Path
p=Path(os.environ['MODEL_DIR']); c=json.loads((p/'config.json').read_text())
print('model_type=',c.get('model_type'),'architectures=',c.get('architectures'))
PY
python - <<'PY' | tee "$OOD_ROOT/logs/evalplus_data.log"
from evalplus.data import get_human_eval_plus, get_mbpp_plus
print('HumanEval+ tasks =', len(get_human_eval_plus()))
print('MBPP+ tasks =', len(get_mbpp_plus()))
PY
python -m pip show evalplus | tee "$OOD_ROOT/logs/evalplus_version.log"
deactivate
