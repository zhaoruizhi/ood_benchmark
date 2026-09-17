#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
# Prefer the known-good legacy venv when it exists.  common.sh may otherwise
# activate a Conda environment with the same name but without EvalPlus.
if [[ -x "$OOD_ROOT/envs/evalplus/bin/python" ]]; then
  source "$OOD_ROOT/envs/evalplus/bin/activate"
elif [[ -x "$OOD_ROOT/venv/bin/python" ]]; then
  source "$OOD_ROOT/venv/bin/activate"
elif declare -F activate_evalplus >/dev/null; then
  activate_evalplus
else
  activate
fi
python -c 'import evalplus; print("EvalPlus runtime:", evalplus.__file__)'

# Four independently sampled pass@1 runs.  Change these only before starting.
SEEDS="${AVG4_SEEDS:-20260917,20260918,20260919,20260920}"
TEMPERATURE="${AVG4_TEMPERATURE:-0.2}"
TOP_P="${AVG4_TOP_P:-0.95}"
TOP_K="${AVG4_TOP_K:--1}"
MAX_NEW_TOKENS="${AVG4_MAX_NEW_TOKENS:-768}"
MAX_MODEL_LEN="${AVG4_MAX_MODEL_LEN:-2048}"
AVG_ROOT="${AVG_ROOT:-$OOD_ROOT/results/evalplus_avg4}"
LOG_ROOT="$AVG_ROOT/logs"
mkdir -p "$AVG_ROOT" "$LOG_ROOT"

python - "$TEMPERATURE" "$TOP_P" "$TOP_K" "$MAX_NEW_TOKENS" "$MAX_MODEL_LEN" <<'PY'
import sys

temperature = float(sys.argv[1])
top_p = float(sys.argv[2])
top_k = int(sys.argv[3])
max_new_tokens = int(sys.argv[4])
max_model_len = int(sys.argv[5])
assert temperature > 0, "AVG4_TEMPERATURE must be > 0 for sampled avg@4"
assert 0 < top_p <= 1, "AVG4_TOP_P must be in (0, 1]"
assert top_k == -1 or top_k > 0, "AVG4_TOP_K must be -1 or a positive integer"
assert max_new_tokens > 0, "AVG4_MAX_NEW_TOKENS must be positive"
assert max_model_len > 0, "AVG4_MAX_MODEL_LEN must be positive"
assert max_new_tokens < max_model_len, (
    "AVG4_MAX_NEW_TOKENS must leave room for the prompt inside AVG4_MAX_MODEL_LEN"
)
PY

python "$ROOT_DIR/scripts/patch_evalplus_vllm_runtime.py"
IFS=',' read -r -a seed_array <<< "$SEEDS"
[[ ${#seed_array[@]} -eq 4 ]] || { echo "AVG4_SEEDS must contain exactly four seeds" >&2; exit 2; }

export EVALPLUS_VLLM_TOP_P="$TOP_P"
export EVALPLUS_VLLM_TOP_K="$TOP_K"
export EVALPLUS_VLLM_MAX_NEW_TOKENS="$MAX_NEW_TOKENS"
export EVALPLUS_VLLM_MAX_MODEL_LEN="$MAX_MODEL_LEN"
export AVG4_SEEDS="$SEEDS"
export AVG4_TEMPERATURE="$TEMPERATURE"

python - "$AVG_ROOT/run_config.json" <<'PY'
import importlib.metadata
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = {
    "model_dir": os.environ["MODEL_DIR"],
    "gpu_id": os.environ["GPU_ID"],
    "tensor_parallel_size": int(os.environ["TP_SIZE"]),
    "seeds": [s.strip() for s in os.environ.get("AVG4_SEEDS", "20260917,20260918,20260919,20260920").split(",")],
    "temperature": float(os.environ.get("AVG4_TEMPERATURE", "0.2")),
    "top_p": float(os.environ["EVALPLUS_VLLM_TOP_P"]),
    "top_k": int(os.environ["EVALPLUS_VLLM_TOP_K"]),
    "max_new_tokens": int(os.environ["EVALPLUS_VLLM_MAX_NEW_TOKENS"]),
    "max_model_len": int(os.environ["EVALPLUS_VLLM_MAX_MODEL_LEN"]),
    "evalplus_version": importlib.metadata.version("evalplus"),
    "vllm_version": importlib.metadata.version("vllm"),
}
if path.exists():
    previous = json.loads(path.read_text())
    if previous != config:
        raise SystemExit(
            f"Refusing to mix incompatible settings in {path.parent}:\n"
            f"existing={json.dumps(previous, sort_keys=True)}\n"
            f"current={json.dumps(config, sort_keys=True)}"
        )
else:
    path.write_text(json.dumps(config, indent=2) + "\n")
print(json.dumps(config, indent=2))
PY

for seed in "${seed_array[@]}"; do
  seed="${seed//[[:space:]]/}"
  run_root="$AVG_ROOT/seed_$seed"
  mkdir -p "$run_root"
  for dataset in humaneval mbpp; do
    EVALPLUS_VLLM_SEED="$seed" evalplus.codegen \
      --model "$MODEL_DIR" --dataset "$dataset" --backend vllm --tp "$TP_SIZE" \
      --temperature "$TEMPERATURE" --n_samples 1 --root "$run_root" \
      2>&1 | tee "$LOG_ROOT/${dataset}_avg4_seed_${seed}_codegen.log"

    sample="$(find "$run_root/$dataset" -type f -name '*.jsonl' ! -name '*.raw.jsonl' ! -name '*eval_results*' | sort | tail -1)"
    test -s "$sample"
    evalplus.syncheck --samples "$sample" --dataset "$dataset" \
      2>&1 | tee "$LOG_ROOT/${dataset}_avg4_seed_${seed}_syncheck.log"
    # EvalPlus executes generated programs; set ALLOW_HOST_EVAL=1 only for the
    # existing controlled host workflow when Docker is unavailable.
    if command -v docker >/dev/null 2>&1; then
      docker run --rm --network none -v "$run_root:/app" ganler/evalplus:latest \
        evalplus.evaluate --dataset "$dataset" --samples "/app/${sample#"$run_root"/}" \
        2>&1 | tee "$LOG_ROOT/${dataset}_avg4_seed_${seed}_evaluate.log"
    elif [[ "${ALLOW_HOST_EVAL:-0}" == "1" ]]; then
      evalplus.evaluate --dataset "$dataset" --samples "$sample" \
        2>&1 | tee "$LOG_ROOT/${dataset}_avg4_seed_${seed}_evaluate.log"
    else
      echo "Docker unavailable; rerun with ALLOW_HOST_EVAL=1 only for controlled host evaluation." >&2
      exit 3
    fi
  done
done

python "$ROOT_DIR/scripts/summarize_evalplus_avg4.py" --root "$AVG_ROOT" --seeds "$SEEDS" \
  | tee "$LOG_ROOT/evalplus_avg4_summary.log"
deactivate
