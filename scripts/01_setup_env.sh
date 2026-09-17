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
# EvalPlus 0.3.1 calls Language(tree_sitter_python.language()), which needs the
# modern one-argument Tree-sitter API. Keep this compatible pair pinned.
python -m pip install -U \
  'transformers==4.55.2' 'tokenizers==0.21.4' \
  'tree-sitter==0.25.0' 'tree-sitter-python==0.25.0' \
  accelerate safetensors datasets 'evalplus[vllm]==0.3.1' 'vllm==0.8.5'
python -c 'from tree_sitter import Language, Parser; import tree_sitter_python; Parser(Language(tree_sitter_python.language())); print("tree-sitter parser compatibility: OK")'
python -m pip check | tee "$OOD_ROOT/logs/pip_check.log"
python - <<'PY'
import torch, transformers
print('torch', torch.__version__, 'cuda', torch.cuda.is_available())
print('transformers', transformers.__version__)
PY
deactivate
