#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
if declare -F activate_evalplus >/dev/null; then activate_evalplus; else activate; fi

# Four independently sampled pass@1 runs.  Change these only before starting.
SEEDS="${AVG4_SEEDS:-20260917,20260918,20260919,20260920}"
TEMPERATURE="${AVG4_TEMPERATURE:-0.2}"
AVG_ROOT="${AVG_ROOT:-$OOD_ROOT/results/evalplus_avg4}"
mkdir -p "$AVG_ROOT"

python "$ROOT_DIR/scripts/patch_evalplus_vllm_seed.py"
IFS=',' read -r -a seed_array <<< "$SEEDS"
[[ ${#seed_array[@]} -eq 4 ]] || { echo "AVG4_SEEDS must contain exactly four seeds" >&2; exit 2; }

for seed in "${seed_array[@]}"; do
  seed="${seed//[[:space:]]/}"
  run_root="$AVG_ROOT/seed_$seed"
  mkdir -p "$run_root"
  for dataset in humaneval mbpp; do
    EVALPLUS_VLLM_SEED="$seed" evalplus.codegen \
      --model "$MODEL_DIR" --dataset "$dataset" --backend vllm --tp "$TP_SIZE" \
      --temperature "$TEMPERATURE" --n_samples 1 --root "$run_root" \
      2>&1 | tee "$OOD_ROOT/logs/${dataset}_avg4_seed_${seed}_codegen.log"

    sample="$(find "$run_root/$dataset" -type f -name '*.jsonl' ! -name '*.raw.jsonl' ! -name '*eval_results*' | sort | tail -1)"
    test -s "$sample"
    evalplus.syncheck --samples "$sample" --dataset "$dataset" \
      2>&1 | tee "$OOD_ROOT/logs/${dataset}_avg4_seed_${seed}_syncheck.log"
    # EvalPlus executes generated programs; set ALLOW_HOST_EVAL=1 only for the
    # existing controlled host workflow when Docker is unavailable.
    if command -v docker >/dev/null 2>&1; then
      docker run --rm --network none -v "$run_root:/app" ganler/evalplus:latest \
        evalplus.evaluate --dataset "$dataset" --samples "/app/${sample#"$run_root"/}" \
        2>&1 | tee "$OOD_ROOT/logs/${dataset}_avg4_seed_${seed}_evaluate.log"
    elif [[ "${ALLOW_HOST_EVAL:-0}" == "1" ]]; then
      evalplus.evaluate --dataset "$dataset" --samples "$sample" \
        2>&1 | tee "$OOD_ROOT/logs/${dataset}_avg4_seed_${seed}_evaluate.log"
    else
      echo "Docker unavailable; rerun with ALLOW_HOST_EVAL=1 only for controlled host evaluation." >&2
      exit 3
    fi
  done
done

python "$ROOT_DIR/scripts/summarize_evalplus_avg4.py" --root "$AVG_ROOT" --seeds "$SEEDS" \
  | tee "$OOD_ROOT/logs/evalplus_avg4_summary.log"
deactivate
