#!/usr/bin/env python3
"""Make EvalPlus v0.3.1 pass EVALPLUS_VLLM_SEED to vLLM's LLM constructor."""
from __future__ import annotations

import importlib.util
from pathlib import Path

spec = importlib.util.find_spec("evalplus.provider.vllm")
if spec is None or spec.origin is None:
    raise SystemExit("EvalPlus is not installed in the active Python environment.")

path = Path(spec.origin)
text = path.read_text()
marker = '"seed": int(os.environ.get("EVALPLUS_VLLM_SEED", "0")),'
if marker in text:
    print(f"seed patch already present: {path}")
    raise SystemExit(0)

if "import os\n" not in text:
    old_import = "from typing import List\n"
    if old_import not in text:
        raise SystemExit(f"unexpected EvalPlus provider layout: {path}")
    text = text.replace(old_import, "import os\n" + old_import, 1)

needle = '            "enable_prefix_caching": True,\n'
if needle not in text:
    raise SystemExit(f"vLLM constructor anchor not found: {path}")
text = text.replace(
    needle,
    needle + '            "seed": int(os.environ.get("EVALPLUS_VLLM_SEED", "0")),\n',
    1,
)
path.write_text(text)
print(f"installed deterministic seed patch: {path}")
