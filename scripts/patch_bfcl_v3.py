#!/usr/bin/env python3
import sys
from pathlib import Path


root = Path(sys.argv[1])
config_path = root / "bfcl_eval/constants/model_config.py"
supported_path = root / "bfcl_eval/constants/supported_models.py"
pyproject_path = root / "pyproject.toml"
config = config_path.read_text()
supported = supported_path.read_text()
pyproject = pyproject_path.read_text()

key = '"Qwen/Qwen3-4B-Instruct-2507-FC"'
if key not in config:
    anchor = '    "Qwen/Qwen3-4B-FC": ModelConfig('
    if anchor not in config:
        raise SystemExit(f"BFCL Qwen3-4B anchor not found in {config_path}")
    entry = '''    "Qwen/Qwen3-4B-Instruct-2507-FC": ModelConfig(
        model_name="Qwen/Qwen3-4B-Instruct-2507",
        display_name="Qwen3-4B-Instruct-2507 (FC)",
        url="https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507",
        org="Qwen",
        license="apache-2.0",
        model_handler=QwenFCHandler,
        input_price=None,
        output_price=None,
        is_fc_model=True,
        underscore_to_dot=False,
    ),
'''
    config = config.replace(anchor, entry + anchor, 1)
    config_path.write_text(config)

if key not in supported:
    anchor = '    "Qwen/Qwen3-4B-FC",'
    if anchor not in supported:
        raise SystemExit(f"BFCL supported-model anchor not found in {supported_path}")
    supported = supported.replace(anchor, f"    {key},\n{anchor}", 1)
    supported_path.write_text(supported)

# The pinned BFCL v3 commit hard-locks cloud-provider SDK versions that are not
# present in the server's offline wheel cache.  These handlers are not used by
# the local Qwen/vLLM profile, but their imports still need installable SDKs.
# Also drop pathlib: it is part of Python 3.10's standard library.
replacements = {
    '    "pathlib",\n': "",
    '    "anthropic==0.53.0",': '    "anthropic==1.6.0",',
    '    "cohere==5.13.3",': '    "cohere==5.18.0",',
    '    "google-genai==1.24.0",': '    "google-genai==2.23.0",',
}
for old, new in replacements.items():
    if old in pyproject:
        pyproject = pyproject.replace(old, new, 1)
    elif new and new not in pyproject:
        raise SystemExit(f"BFCL dependency anchor not found in {pyproject_path}: {old!r}")
pyproject_path.write_text(pyproject)

print(f"patched {root}")
