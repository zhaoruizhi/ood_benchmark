#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
if command -v conda >/dev/null 2>&1; then
  source "$(conda info --base)/etc/profile.d/conda.sh"
  conda env list | awk '{print $1}' | grep -qx "$ENV_NAME" || conda create -y -n "$ENV_NAME" python=3.11
  conda activate "$ENV_NAME"
else
  python3 -m venv "$(venv)"
  activate
fi
python -m pip install -U pip setuptools wheel
python -m pip install -U 'transformers>=4.51.0' accelerate safetensors datasets 'evalplus[vllm]' vllm
python -m pip check | tee "$OOD_ROOT/logs/pip_check.log"
python - <<'PY'
import torch, transformers
print('torch', torch.__version__, 'cuda', torch.cuda.is_available())
print('transformers', transformers.__version__)
PY
deactivate
