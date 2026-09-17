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

prompt_path = path.parent / "prompts/test_output_prediction.py"
prompt_text = prompt_path.read_text()
compat_import = '''try:
    from anthropic import HUMAN_PROMPT, AI_PROMPT
except ImportError:
    # Removed by newer Anthropic SDKs; retained for legacy prompt formatting.
    HUMAN_PROMPT = "\\n\\nHuman:"
    AI_PROMPT = "\\n\\nAssistant:"'''
header = "import json\n\n"
next_import = "from lcb_runner.lm_styles import LMStyle"
if not prompt_text.startswith(header) or next_import not in prompt_text:
    raise SystemExit(f"LiveCodeBench prompt import anchors not found in {prompt_path}")
tail = prompt_text[prompt_text.index(next_import):]
prompt_path.write_text(f"{header}{compat_import}\n\n{tail}")

# Some scenarios repeat the same removed constants import.  Replace only a
# complete, unindented import line so already guarded imports remain untouched.
old_import = "from anthropic import HUMAN_PROMPT, AI_PROMPT"
for other_prompt in (path.parent / "prompts").glob("*.py"):
    lines = other_prompt.read_text().splitlines()
    if old_import in lines:
        line_index = lines.index(old_import)
        replacement = compat_import.splitlines()
        lines[line_index : line_index + 1] = replacement
        other_prompt.write_text("\n".join(lines) + "\n")

print(f"patched {path}")
