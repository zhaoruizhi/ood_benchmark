#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; activate
BFCL_DIR="$OOD_ROOT/repos/gorilla"
if [[ ! -d "$BFCL_DIR/.git" ]]; then git clone https://github.com/ShishirPatil/gorilla.git "$BFCL_DIR"; fi
cd "$BFCL_DIR/berkeley-function-call-leaderboard"; git -C "$BFCL_DIR" rev-parse HEAD | tee "$OOD_ROOT/logs/bfcl_commit.log"
python -m pip install -e '.[oss_eval_vllm]'; python -m pip check | tee "$OOD_ROOT/logs/bfcl_pip_check.log"
export BFCL_PROJECT_ROOT="$OOD_ROOT/results/bfcl"; mkdir -p "$BFCL_PROJECT_ROOT"; cp -n bfcl_eval/.env.example "$BFCL_PROJECT_ROOT/.env" 2>/dev/null || true
export BFCL_MODEL='Qwen/Qwen3-4B-Instruct-2507-FC'
V3_CATS=(simple_python simple_java simple_javascript parallel multiple parallel_multiple irrelevance live_simple live_multiple live_parallel live_parallel_multiple live_irrelevance live_relevance multi_turn_base multi_turn_miss_func multi_turn_miss_param multi_turn_long_context)
for CAT in "${V3_CATS[@]}"; do
  bfcl generate --model "$BFCL_MODEL" --test-category "$CAT" --backend vllm --num-gpus 1 --gpu-memory-utilization "$VLLM_GPU_MEMORY_UTILIZATION" --local-model-path "$MODEL_DIR" --include-input-log 2>&1 | tee "$OOD_ROOT/logs/bfcl_generate_${CAT}.log"
  bfcl evaluate --model "$BFCL_MODEL" --test-category "$CAT" 2>&1 | tee "$OOD_ROOT/logs/bfcl_evaluate_${CAT}.log"
done
deactivate
