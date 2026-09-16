#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; activate
MODEL_DIR="$MODEL_DIR" python - <<'PY'
import os
from transformers import AutoTokenizer, AutoModelForCausalLM
p=os.environ['MODEL_DIR']
tok=AutoTokenizer.from_pretrained(p, local_files_only=True)
model=AutoModelForCausalLM.from_pretrained(p, torch_dtype='auto', device_map='auto', local_files_only=True)
msg=[{'role':'user','content':'Write one Python function add(a, b) that returns a+b. Return code only.'}]
text=tok.apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
x=tok(text, return_tensors='pt').to(model.device)
y=model.generate(**x, max_new_tokens=64, do_sample=False)
print(tok.decode(y[0][x.input_ids.shape[-1]:], skip_special_tokens=True))
PY
deactivate
