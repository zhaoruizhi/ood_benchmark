#!/usr/bin/env python3
"""Patch EvalPlus v0.3.1's vLLM provider for reproducible runtime settings.

EvalPlus v0.3.1 hard-codes ``max_model_len=2048`` and ``top_p=0.95`` and
does not expose vLLM's ``top_k``.  The benchmark launcher exports the
following variables, which this patch wires into the provider:

* EVALPLUS_VLLM_SEED
* EVALPLUS_VLLM_TOP_P
* EVALPLUS_VLLM_TOP_K
* EVALPLUS_VLLM_MAX_NEW_TOKENS
* EVALPLUS_VLLM_MAX_MODEL_LEN

The transformation is idempotent and keeps EvalPlus defaults when a variable
is absent.  ``--path`` exists so the transformation can be tested without
modifying an installed package.
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path


def patch_source(text: str) -> tuple[str, list[str]]:
    changes: list[str] = []

    if "import os\n" not in text:
        anchor = "from typing import List\n"
        if anchor not in text:
            raise ValueError("unexpected EvalPlus provider: typing import not found")
        text = text.replace(anchor, "import os\n" + anchor, 1)
        changes.append("import os")

    seed_line = '            "seed": int(os.environ.get("EVALPLUS_VLLM_SEED", "0")),\n'
    if "EVALPLUS_VLLM_SEED" not in text:
        anchor = '            "enable_prefix_caching": True,\n'
        if anchor not in text:
            raise ValueError("unexpected EvalPlus provider: LLM kwargs anchor not found")
        text = text.replace(anchor, anchor + seed_line, 1)
        changes.append("seed")

    if "EVALPLUS_VLLM_MAX_MODEL_LEN" not in text:
        anchor = "        self.llm = LLM(model=name, max_model_len=2048, **kwargs)\n"
        replacement = (
            "        max_model_len = int(\n"
            '            os.environ.get("EVALPLUS_VLLM_MAX_MODEL_LEN", "2048")\n'
            "        )\n"
            "        self.llm = LLM(model=name, max_model_len=max_model_len, **kwargs)\n"
        )
        if anchor not in text:
            raise ValueError("unexpected EvalPlus provider: max_model_len anchor not found")
        text = text.replace(anchor, replacement, 1)
        changes.append("max_model_len")

    if "EVALPLUS_VLLM_MAX_NEW_TOKENS" not in text:
        anchor = "                max_tokens=self.max_new_tokens,\n"
        replacement = (
            "                max_tokens=int(\n"
            "                    os.environ.get(\n"
            '                        "EVALPLUS_VLLM_MAX_NEW_TOKENS", str(self.max_new_tokens)\n'
            "                    )\n"
            "                ),\n"
        )
        if anchor not in text:
            raise ValueError("unexpected EvalPlus provider: max_tokens anchor not found")
        text = text.replace(anchor, replacement, 1)
        changes.append("max_new_tokens")

    if "EVALPLUS_VLLM_TOP_P" not in text:
        anchor = "                top_p=0.95 if do_sample else 1.0,\n"
        replacement = (
            "                top_p=(\n"
            '                    float(os.environ.get("EVALPLUS_VLLM_TOP_P", "0.95"))\n'
            "                    if do_sample\n"
            "                    else 1.0\n"
            "                ),\n"
        )
        if anchor not in text:
            raise ValueError("unexpected EvalPlus provider: top_p anchor not found")
        text = text.replace(anchor, replacement, 1)
        changes.append("top_p")

    if "EVALPLUS_VLLM_TOP_K" not in text:
        anchor = "                stop=self.eos,\n"
        replacement = (
            "                top_k=(\n"
            '                    int(os.environ.get("EVALPLUS_VLLM_TOP_K", "-1"))\n'
            "                    if do_sample\n"
            "                    else -1\n"
            "                ),\n"
            + anchor
        )
        if anchor not in text:
            raise ValueError("unexpected EvalPlus provider: stop anchor not found")
        text = text.replace(anchor, replacement, 1)
        changes.append("top_k")

    compile(text, "evalplus.provider.vllm", "exec")
    return text, changes


def installed_provider_path() -> Path:
    spec = importlib.util.find_spec("evalplus.provider.vllm")
    if spec is None or spec.origin is None:
        raise SystemExit("EvalPlus is not installed in the active Python environment.")
    return Path(spec.origin)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", type=Path, help="patch this provider file instead of site-packages")
    args = parser.parse_args()
    path = args.path or installed_provider_path()

    original = path.read_text()
    patched, changes = patch_source(original)
    if not changes:
        print(f"EvalPlus vLLM runtime patch already present: {path}")
        return

    backup = path.with_suffix(path.suffix + ".ood-benchmark.bak")
    if not backup.exists():
        backup.write_text(original)
    path.write_text(patched)
    print(f"patched EvalPlus vLLM provider ({', '.join(changes)}): {path}")
    print(f"original provider backup: {backup}")


if __name__ == "__main__":
    main()
