#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"; activate
export EP_ROOT="$OOD_ROOT/results/evalplus"; mkdir -p "$EP_ROOT"
evalplus.codegen --model "$MODEL_DIR" --dataset humaneval --backend vllm --greedy --root "$EP_ROOT" 2>&1 | tee "$OOD_ROOT/logs/humaneval_codegen.log"
evalplus.codegen --model "$MODEL_DIR" --dataset mbpp --backend vllm --greedy --root "$EP_ROOT" 2>&1 | tee "$OOD_ROOT/logs/mbpp_codegen.log"
HE_SAMPLE=$(find "$EP_ROOT/humaneval" -type f -name '*.jsonl' ! -name '*eval_results*' | sort | tail -1)
MBPP_SAMPLE=$(find "$EP_ROOT/mbpp" -type f -name '*.jsonl' ! -name '*eval_results*' | sort | tail -1)
test -s "$HE_SAMPLE" && test -s "$MBPP_SAMPLE"
evalplus.syncheck --samples "$HE_SAMPLE" --dataset humaneval | tee "$OOD_ROOT/logs/humaneval_syncheck.log" || true
evalplus.syncheck --samples "$MBPP_SAMPLE" --dataset mbpp | tee "$OOD_ROOT/logs/mbpp_syncheck.log" || true
if command -v docker >/dev/null 2>&1; then
  docker run --rm --network none -v "$EP_ROOT:/app" ganler/evalplus:latest evalplus.evaluate --dataset humaneval --samples "/app/${HE_SAMPLE#"$EP_ROOT"/}" 2>&1 | tee "$OOD_ROOT/logs/humaneval_evaluate.log"
  docker run --rm --network none -v "$EP_ROOT:/app" ganler/evalplus:latest evalplus.evaluate --dataset mbpp --samples "/app/${MBPP_SAMPLE#"$EP_ROOT"/}" 2>&1 | tee "$OOD_ROOT/logs/mbpp_evaluate.log"
else
  echo 'Docker unavailable; host execution is less isolated.' | tee "$OOD_ROOT/logs/evalplus_isolation_warning.log"
  evalplus.evaluate --dataset humaneval --samples "$HE_SAMPLE" 2>&1 | tee "$OOD_ROOT/logs/humaneval_evaluate.log"
  evalplus.evaluate --dataset mbpp --samples "$MBPP_SAMPLE" 2>&1 | tee "$OOD_ROOT/logs/mbpp_evaluate.log"
fi
deactivate
