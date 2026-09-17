#!/usr/bin/env python3
import re
import sys
from pathlib import Path


path = Path(sys.argv[1])
text = path.read_text()
entry_pattern = re.compile(
    r"\n\s*LanguageModel\(\s*\n\s*\"Qwen/Qwen3-4B-Instruct-2507\".*?\n\s*\),",
    re.DOTALL,
)
text = entry_pattern.sub("", text)
anchor_pattern = re.compile(
    r"\n\]\s*\nLanguageModelStore: dict\[str, LanguageModel\] = \{"
)
if not anchor_pattern.search(text):
    raise SystemExit(f"LiveCodeBench model-list anchor not found in {path}")
entry = '''
    LanguageModel(
        "Qwen/Qwen3-4B-Instruct-2507",
        "Qwen3-4B-Instruct-2507",
        LMStyle.CodeQwenInstruct,
        datetime(2025, 7, 1),
        link="https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507",
    ),'''
text = anchor_pattern.sub(
    f"{entry}\n]\n\nLanguageModelStore: dict[str, LanguageModel] = {{",
    text,
    count=1,
)
path.write_text(text)
print(f"patched {path}")
