# Qwen3-4B-Instruct-2507 跨域 OOD Benchmark Runbook

本文针对 `Qwen/Qwen3-4B-Instruct-2507`，给出 HumanEval+、MBPP+、LiveCodeBench release_v6 和 BFCL v3 的可复现实验流程。用户给出的列表中 MBPP+ 重复了一次，实验只运行一次。

## 0. 实验约定

| 项目 | 约定 |
|---|---|
| 模型 | `Qwen/Qwen3-4B-Instruct-2507`；这是 Instruct checkpoint |
| GPU | 当前 GPU 0、2、3 有任务，优先用空闲 GPU 1；开始每个阶段前重新检查显存 |
| HumanEval+/MBPP+ | EvalPlus；主报告 `Base + Extra` 的 `pass@1`，同时保留 Base |
| LCB | `release_v6`、`codegeneration`；完整题集用 `--not_fast`；报告 `pass@1/pass@5` |
| BFCL | 显式运行 v3 类别，使用 `Qwen/Qwen3-4B-Instruct-2507-FC` 配置 |

BFCL v3 类别：

```text
simple_python simple_java simple_javascript parallel multiple parallel_multiple irrelevance
live_simple live_multiple live_parallel live_parallel_multiple live_irrelevance live_relevance
multi_turn_base multi_turn_miss_func multi_turn_miss_param multi_turn_long_context
```

## 1. 服务器与 GPU 预检

不要杀掉 GPU 0、2、3 上的已有进程。

```bash
nvidia-smi
nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu --format=csv
ps -ef | rg 'vllm|VLLM|python|bfcl|lcb_runner' || true
export GPU_ID=${GPU_ID:-1}
nvidia-smi -i "$GPU_ID" --query-gpu=index,memory.total,memory.used,utilization.gpu --format=csv

tmux new -s qwen3-ood
# 断线重连：tmux attach -t qwen3-ood
```

4B 模型放在一张 H200 上即可；设置 `CUDA_VISIBLE_DEVICES=$GPU_ID` 后，进程内部看到的 `cuda:0` 就是该物理卡。

## 2. 目录、HF 缓存与模型下载

```bash
export RUN_ROOT="$(pwd)/run_qwen3_ood"
export MODEL_ID="Qwen/Qwen3-4B-Instruct-2507"
export MODEL_DIR="$RUN_ROOT/models/Qwen3-4B-Instruct-2507"
export HF_HOME="$RUN_ROOT/hf_cache"
export HF_DATASETS_CACHE="$HF_HOME/datasets"
mkdir -p "$RUN_ROOT" "$MODEL_DIR" "$HF_HOME" "$RUN_ROOT/logs"

python3 -m pip install -U huggingface_hub
# 公共仓库不需要 token；如遇限流，先执行 hf auth login
hf download "$MODEL_ID" --local-dir "$MODEL_DIR" 2>&1 | tee "$RUN_ROOT/logs/model_download.log"
test -f "$MODEL_DIR/config.json" && test -f "$MODEL_DIR/tokenizer_config.json"
du -sh "$MODEL_DIR"

MODEL_DIR="$MODEL_DIR" python3 - <<'PY'
import os, json, pathlib
p = pathlib.Path(os.environ['MODEL_DIR'])
cfg = json.loads((p/'config.json').read_text())
print('model_type=', cfg.get('model_type'))
print('architectures=', cfg.get('architectures'))
PY
```

## 3. 最小模型 smoke test

```bash
python3 -m venv "$RUN_ROOT/venv-smoke"
source "$RUN_ROOT/venv-smoke/bin/activate"
python -m pip install -U pip setuptools wheel
python -m pip install -U 'transformers>=4.51.0' accelerate safetensors
python -m pip check

MODEL_DIR="$MODEL_DIR" CUDA_VISIBLE_DEVICES="$GPU_ID" python - <<'PY'
import os
from transformers import AutoTokenizer, AutoModelForCausalLM
p = os.environ['MODEL_DIR']
tok = AutoTokenizer.from_pretrained(p, local_files_only=True)
model = AutoModelForCausalLM.from_pretrained(p, torch_dtype='auto', device_map='auto', local_files_only=True)
msg = [{'role':'user','content':'Write one Python function add(a, b) that returns a+b. Return code only.'}]
text = tok.apply_chat_template(msg, tokenize=False, add_generation_prompt=True)
x = tok(text, return_tensors='pt').to(model.device)
y = model.generate(**x, max_new_tokens=64, do_sample=False)
print(tok.decode(y[0][x.input_ids.shape[-1]:], skip_special_tokens=True))
PY
deactivate
```

如果出现 `KeyError: qwen3`，升级 Transformers 后再继续。smoke 成功只证明模型可载入。

## 4. HumanEval+ 与 MBPP+（EvalPlus）

EvalPlus 首次调用会获取两个扩展测试集。先生成，再隔离执行测试。

```bash
python3 -m venv "$RUN_ROOT/venv-evalplus"
source "$RUN_ROOT/venv-evalplus/bin/activate"
python -m pip install -U pip
python -m pip install -U 'evalplus[vllm]' 'transformers>=4.51.0'
python -m pip check

export CUDA_VISIBLE_DEVICES="$GPU_ID"
export EP_ROOT="$RUN_ROOT/evalplus_results"
mkdir -p "$EP_ROOT"
python - <<'PY'
from evalplus.data import get_human_eval_plus, get_mbpp_plus
print('HumanEval+ tasks:', len(get_human_eval_plus()))
print('MBPP+ tasks:', len(get_mbpp_plus()))
PY

evalplus.codegen --model "$MODEL_DIR" --dataset humaneval --backend vllm --greedy --root "$EP_ROOT" 2>&1 | tee "$RUN_ROOT/logs/humaneval_codegen.log"
evalplus.codegen --model "$MODEL_DIR" --dataset mbpp --backend vllm --greedy --root "$EP_ROOT" 2>&1 | tee "$RUN_ROOT/logs/mbpp_codegen.log"
find "$EP_ROOT" -type f -name '*.jsonl' -print | sort
```

语法检查和评测：

```bash
HE_SAMPLE="$(find "$EP_ROOT/humaneval" -type f -name '*.jsonl' ! -name '*eval_results*' | sort | tail -1)"
MBPP_SAMPLE="$(find "$EP_ROOT/mbpp" -type f -name '*.jsonl' ! -name '*eval_results*' | sort | tail -1)"
test -s "$HE_SAMPLE" && test -s "$MBPP_SAMPLE"
HE_REL="${HE_SAMPLE#"$EP_ROOT"/}"; MBPP_REL="${MBPP_SAMPLE#"$EP_ROOT"/}"
evalplus.syncheck --samples "$HE_SAMPLE" --dataset humaneval 2>&1 | tee "$RUN_ROOT/logs/humaneval_syncheck.log" || true
evalplus.syncheck --samples "$MBPP_SAMPLE" --dataset mbpp 2>&1 | tee "$RUN_ROOT/logs/mbpp_syncheck.log" || true

if command -v docker >/dev/null 2>&1; then
  docker run --rm --network none -v "$EP_ROOT:/app" ganler/evalplus:latest evalplus.evaluate --dataset humaneval --samples "/app/$HE_REL" 2>&1 | tee "$RUN_ROOT/logs/humaneval_evaluate.log"
  docker run --rm --network none -v "$EP_ROOT:/app" ganler/evalplus:latest evalplus.evaluate --dataset mbpp --samples "/app/$MBPP_REL" 2>&1 | tee "$RUN_ROOT/logs/mbpp_evaluate.log"
else
  echo 'Docker 不可用；确认隔离策略后再在宿主机执行。'
  evalplus.evaluate --dataset humaneval --samples "$HE_SAMPLE" 2>&1 | tee "$RUN_ROOT/logs/humaneval_evaluate.log"
  evalplus.evaluate --dataset mbpp --samples "$MBPP_SAMPLE" 2>&1 | tee "$RUN_ROOT/logs/mbpp_evaluate.log"
fi
deactivate
```

日志应出现 `Base` 和 `Base + Extra`。正式表通常取 `Base + Extra/pass@1`，同时保留样本 JSONL、评测 JSONL 和日志。

## 5. LiveCodeBench release_v6

当前 LCB 模型表可能没有该精确 Qwen3 名称；下面补充 `CodeQwenInstruct` 风格条目。
LCB 的 release 数据由官方 runner 在第一次运行时下载并缓存到 `HF_HOME`；因此第 2 节的 `HF_HOME` 必须在运行前保持一致。

```bash
git clone https://github.com/LiveCodeBench/LiveCodeBench.git "$RUN_ROOT/LiveCodeBench"
cd "$RUN_ROOT/LiveCodeBench"
git rev-parse HEAD | tee "$RUN_ROOT/logs/livecodebench_git_rev.txt"
python3 -m venv "$RUN_ROOT/venv-lcb"
source "$RUN_ROOT/venv-lcb/bin/activate"
python -m pip install -U pip
python -m pip install -e .
python -m pip install -U 'transformers>=4.51.0' vllm
python -m pip check

python - <<'PY'
from pathlib import Path
p = Path('lcb_runner/lm_styles.py')
s = p.read_text(); needle = 'LanguageModelStore: dict[str, LanguageModel] = {'
entry = '''    LanguageModel(
        "Qwen/Qwen3-4B-Instruct-2507",
        "Qwen3-4B-Instruct-2507",
        LMStyle.CodeQwenInstruct,
        datetime(2025, 7, 1),
        link="https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507",
    ),
'''
if '"Qwen/Qwen3-4B-Instruct-2507"' not in s:
    p.write_text(s.replace(needle, entry + needle))
PY
python - <<'PY'
from lcb_runner.lm_styles import LanguageModelStore
assert 'Qwen/Qwen3-4B-Instruct-2507' in LanguageModelStore
print(LanguageModelStore['Qwen/Qwen3-4B-Instruct-2507'])
PY

export CUDA_VISIBLE_DEVICES="$GPU_ID"
export LCB_OUT="$RUN_ROOT/livecodebench_output"
mkdir -p "$LCB_OUT"
python -m lcb_runner.runner.main \
  --model 'Qwen/Qwen3-4B-Instruct-2507' \
  --local_model_path "$MODEL_DIR" \
  --scenario codegeneration \
  --release_version release_v6 \
  --tensor_parallel_size 1 \
  --not_fast --use_cache --evaluate \
  2>&1 | tee "$RUN_ROOT/logs/lcb_v6.log"
cp -a output/. "$LCB_OUT/"
```

若 parser 不接受 `--not_fast`，先看 `python -m lcb_runner.runner.main --help`，不能把默认 lite 结果标成完整 v6。保存生成文件、evaluation 文件、`pass@1/pass@5`、release 和 timeout 参数。

## 6. BFCL v3

BFCL 官方配置包含 `Qwen/Qwen3-4B-Instruct-2507-FC`，使用 `<tool_call>...</tool_call>` 格式。让 BFCL 的 vLLM backend 管理本地模型，避免手工 endpoint 与 handler 格式不一致。
BFCL 的测试 JSON 和 checker 随官方仓库一起安装，不需要另找一个同名 Hugging Face 数据集。

```bash
git clone https://github.com/ShishirPatil/gorilla.git "$RUN_ROOT/gorilla"
cd "$RUN_ROOT/gorilla/berkeley-function-call-leaderboard"
git rev-parse HEAD | tee "$RUN_ROOT/logs/bfcl_git_rev.txt"
python3 -m venv "$RUN_ROOT/venv-bfcl"
source "$RUN_ROOT/venv-bfcl/bin/activate"
python -m pip install -U pip
python -m pip install -e '.[oss_eval_vllm]'
python -m pip check

export BFCL_PROJECT_ROOT="$RUN_ROOT/bfcl_project"
mkdir -p "$BFCL_PROJECT_ROOT"
cp -n bfcl_eval/.env.example "$BFCL_PROJECT_ROOT/.env" || true
bfcl test-categories | tee "$RUN_ROOT/logs/bfcl_test_categories.txt"
rg -n 'Qwen/Qwen3-4B-Instruct-2507' bfcl_eval/constants/model_config.py | tee "$RUN_ROOT/logs/bfcl_qwen_models.txt"

export CUDA_VISIBLE_DEVICES="$GPU_ID"
export BFCL_MODEL='Qwen/Qwen3-4B-Instruct-2507-FC'
export BFCL_LOCAL_MODEL="$MODEL_DIR"
V3_CATS=(simple_python simple_java simple_javascript parallel multiple parallel_multiple irrelevance live_simple live_multiple live_parallel live_parallel_multiple live_irrelevance live_relevance multi_turn_base multi_turn_miss_func multi_turn_miss_param multi_turn_long_context)
for CAT in "${V3_CATS[@]}"; do
  echo "===== BFCL v3: $CAT ====="
  bfcl generate --model "$BFCL_MODEL" --test-category "$CAT" --backend vllm --num-gpus 1 --gpu-memory-utilization 0.90 --local-model-path "$BFCL_LOCAL_MODEL" --include-input-log 2>&1 | tee "$RUN_ROOT/logs/bfcl_generate_${CAT}.log"
  bfcl evaluate --model "$BFCL_MODEL" --test-category "$CAT" 2>&1 | tee "$RUN_ROOT/logs/bfcl_evaluate_${CAT}.log"
done
deactivate
```

结果在 `$BFCL_PROJECT_ROOT/score/`，原始回答在 `result/`。确认文件名含 `BFCL_v3_`；正式分数不要使用 `--partial-eval`。

## 7. 统一证据清单与报告表

```bash
cd "$RUN_ROOT"
{
  date -Is
  nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used --format=csv
  python3 --version
  git -C "$RUN_ROOT/LiveCodeBench" rev-parse HEAD 2>/dev/null || true
  git -C "$RUN_ROOT/gorilla" rev-parse HEAD 2>/dev/null || true
  find "$RUN_ROOT" -maxdepth 4 -type f \( -name '*.json' -o -name '*.jsonl' -o -name '*.log' -o -name '*.csv' \) -print | sort
} | tee "$RUN_ROOT/experiment_manifest.txt"
```

| benchmark | release | 主指标 |
|---|---|---|
| HumanEval+ | EvalPlus | Base + Extra `pass@1` |
| MBPP+ | EvalPlus | Base + Extra `pass@1` |
| LCB | `release_v6`, full `--not_fast` | `pass@1`, `pass@5` |
| BFCL | v3 类别 | overall、single-turn、multi-turn、category accuracy |

不要对四个 benchmark 的分数做平均；代码生成和工具调用的输入协议、执行器、指标都不同。报告中保留模型/HF revision、三个 harness commit、Python/vLLM/Transformers 版本、GPU、完整命令、原始输出和日志。

## 8. 常见故障

- OOM：确认未误用 GPU 0、2、3；改用空闲卡，vLLM 显存利用率降到 0.80，或将最大长度降到 32768。
- `KeyError: qwen3`：升级 `transformers>=4.51.0`。
- LCB unknown model：确认 `lm_styles.py` 补丁和精确模型字符串。
- BFCL 无 Qwen alias：检查 `model_config.py` 中是否有 `Qwen/Qwen3-4B-Instruct-2507-FC` 且 handler 为 `QwenFCHandler`。
- BFCL 解析失败：先只跑 `simple_python`，检查 `--include-input-log` 中是否出现 `<tool_call>`；保留原始响应。
- LCB timeout：记录 `--timeout`、`--num_process_evaluate`；改变后必须在同一 release 重跑。
