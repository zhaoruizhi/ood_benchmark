# paratera-h100 上执行 Qwen3-4B OOD Benchmark

## 已确认的远程状态

通过 SSH 别名 `paratera-h100` 已成功连接：

- 主机：`d1n41d27g02`
- 用户：`tlwang`
- 工作目录：`/home/tlwang`
- 模型目录：`/ssd/tlwang/opsd/models/Qwen3-4B-Instruct-2507`
- 模型大小：约 7.6 GB
- `config.json`：`model_type=qwen3`，`torch_dtype=bfloat16`
- `/ssd/tlwang/baseline` 当前只有空的 `runbook.md`
- 8 张 H100 当前全部被训练任务占用；不要停止这些任务，也不要在它们运行时抢 GPU

下面的命令都应在远程终端执行。

## 1. 进入服务器，建立实验目录

```bash
ssh paratera-h100
mkdir -p /ssd/tlwang/baseline/ood_benchmark/{logs,cache,repos,results}
cd /ssd/tlwang/baseline/ood_benchmark

export OOD_ROOT=/ssd/tlwang/baseline/ood_benchmark
export MODEL_DIR=/ssd/tlwang/opsd/models/Qwen3-4B-Instruct-2507
export HF_HOME=$OOD_ROOT/cache/huggingface
export HF_DATASETS_CACHE=$OOD_ROOT/cache/huggingface/datasets
mkdir -p "$HF_HOME" "$HF_DATASETS_CACHE"

test -f "$MODEL_DIR/config.json" && test -f "$MODEL_DIR/tokenizer_config.json"
```

截图中已有代理环境变量时，保留它们；不要把代理用户名、密码或 token 写进 runbook。

## 2. 先确认 GPU 是否空闲

```bash
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv
ps -eo pid,user,etime,cmd | grep -E '[v]llm|[t]orchrun|[a]ccelerate|[r]un_opsd' | head -80
```

只有出现一张专用空闲卡后才运行模型评测。假设物理 GPU 4 空闲时：

```bash
export GPU_ID=4
export CUDA_VISIBLE_DEVICES=$GPU_ID
```

如果训练结束后空闲的是别的卡，只改 `GPU_ID`。不要使用当前仍在训练的 GPU。

## 3. 建议建立独立评测环境

不要把 EvalPlus、LiveCodeBench、BFCL 直接安装到正在运行 OPSD 的 `/ssd/tlwang/opsd/venv`。

```bash
python3 -m venv "$OOD_ROOT/venv"
source "$OOD_ROOT/venv/bin/activate"
python -m pip install -U pip setuptools wheel
python -m pip install -U 'transformers>=4.51.0' accelerate safetensors datasets
python -m pip check
```

如果这台服务器已经有可复用的 vLLM CUDA 环境，可先检查：

```bash
python - <<'PY'
import importlib.util
for x in ['torch','transformers','vllm']:
    print(x, bool(importlib.util.find_spec(x)))
PY
```

若新 venv 中没有可用 vLLM，再在确认 GPU 空闲后安装：

```bash
python -m pip install -U vllm
python -m pip check
```

## 4. 下载/缓存 HumanEval+ 和 MBPP+ 数据集

EvalPlus 的数据集由官方 Python 包管理。下面会下载并打印题目数量；这一步不生成模型输出。

```bash
python -m pip install -U 'evalplus[vllm]'

python - <<'PY'
from evalplus.data import get_human_eval_plus, get_mbpp_plus
he = get_human_eval_plus()
mbpp = get_mbpp_plus()
print('HumanEval+ tasks =', len(he))
print('MBPP+ tasks =', len(mbpp))
PY
```

保存缓存和版本：

```bash
python -m pip show evalplus | tee "$OOD_ROOT/logs/evalplus_version.txt"
```

MBPP+ 在用户列表中重复了一次，实验只运行一次。

## 5. 下载/安装 LiveCodeBench release_v6

LiveCodeBench 的 release 数据由官方 runner 按 `--release_version release_v6` 下载并缓存，不要用其他 release 的结果冒充 v6。

```bash
cd "$OOD_ROOT/repos"
git clone --depth 1 https://github.com/LiveCodeBench/LiveCodeBench.git
cd LiveCodeBench
git rev-parse HEAD | tee "$OOD_ROOT/logs/livecodebench_commit.txt"
python -m pip install -e .
python -m pip check
```

当前模型表可能没有这个精确模型名，补充一个 Qwen3 Instruct 条目：

```bash
python - <<'PY'
from pathlib import Path
p = Path('lcb_runner/lm_styles.py')
s = p.read_text()
needle = 'LanguageModelStore: dict[str, LanguageModel] = {'
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
```

## 6. 下载/安装 BFCL v3

BFCL 的 benchmark 数据和 checker 随官方仓库一起获得；clone 仓库就是下载 BFCL 数据和评测代码。

```bash
cd "$OOD_ROOT/repos"
git clone --depth 1 https://github.com/ShishirPatil/gorilla.git
git -C gorilla rev-parse HEAD | tee "$OOD_ROOT/logs/bfcl_commit.txt"
cd gorilla/berkeley-function-call-leaderboard
python -m pip install -e '.[oss_eval_vllm]'
python -m pip check

export BFCL_PROJECT_ROOT=$OOD_ROOT/results/bfcl
mkdir -p "$BFCL_PROJECT_ROOT"
cp -n bfcl_eval/.env.example "$BFCL_PROJECT_ROOT/.env" || true
rg -n 'Qwen/Qwen3-4B-Instruct-2507' bfcl_eval/constants/model_config.py
bfcl test-categories | tee "$OOD_ROOT/logs/bfcl_categories.txt"
command -v node || true
command -v java || true
```

如果 `node` 或 `java` 不存在，先安装对应运行时，否则 Java/JavaScript 类别不能完成正式评测。

## 7. HumanEval+ 和 MBPP+ 生成与评测

每个 harness 必须顺序运行；不要同时启动 EvalPlus、LCB 和 BFCL。

```bash
source "$OOD_ROOT/venv/bin/activate"
export CUDA_VISIBLE_DEVICES=$GPU_ID
export EP_ROOT=$OOD_ROOT/results/evalplus
mkdir -p "$EP_ROOT"

evalplus.codegen --model "$MODEL_DIR" --dataset humaneval --backend vllm \
  --greedy --root "$EP_ROOT" 2>&1 | tee "$OOD_ROOT/logs/humaneval_codegen.log"
evalplus.codegen --model "$MODEL_DIR" --dataset mbpp --backend vllm \
  --greedy --root "$EP_ROOT" 2>&1 | tee "$OOD_ROOT/logs/mbpp_codegen.log"

HE_SAMPLE=$(find "$EP_ROOT/humaneval" -type f -name '*.jsonl' ! -name '*eval_results*' | sort | tail -1)
MBPP_SAMPLE=$(find "$EP_ROOT/mbpp" -type f -name '*.jsonl' ! -name '*eval_results*' | sort | tail -1)
test -s "$HE_SAMPLE" && test -s "$MBPP_SAMPLE"

evalplus.syncheck --samples "$HE_SAMPLE" --dataset humaneval | tee "$OOD_ROOT/logs/humaneval_syncheck.log" || true
evalplus.syncheck --samples "$MBPP_SAMPLE" --dataset mbpp | tee "$OOD_ROOT/logs/mbpp_syncheck.log" || true
```

优先用 Docker 执行生成代码：

```bash
HE_REL=${HE_SAMPLE#"$EP_ROOT"/}
MBPP_REL=${MBPP_SAMPLE#"$EP_ROOT"/}
docker run --rm --network none -v "$EP_ROOT:/app" ganler/evalplus:latest \
  evalplus.evaluate --dataset humaneval --samples "/app/$HE_REL" \
  2>&1 | tee "$OOD_ROOT/logs/humaneval_evaluate.log"
docker run --rm --network none -v "$EP_ROOT:/app" ganler/evalplus:latest \
  evalplus.evaluate --dataset mbpp --samples "/app/$MBPP_REL" \
  2>&1 | tee "$OOD_ROOT/logs/mbpp_evaluate.log"
```

日志里必须出现 `Base` 和 `Base + Extra`。正式报告主指标取 `Base + Extra/pass@1`，同时保存原始 JSONL 和评测日志。

## 8. LiveCodeBench release_v6

```bash
cd "$OOD_ROOT/repos/LiveCodeBench"
export CUDA_VISIBLE_DEVICES=$GPU_ID
python -m lcb_runner.runner.main \
  --model 'Qwen/Qwen3-4B-Instruct-2507' \
  --local_model_path "$MODEL_DIR" \
  --scenario codegeneration \
  --release_version release_v6 \
  --tensor_parallel_size 1 \
  --not_fast --use_cache --evaluate \
  2>&1 | tee "$OOD_ROOT/logs/lcb_release_v6.log"
```

`--not_fast` 用于完整 code-generation 题集；没有它时不要把默认 lite 结果标成完整 v6。结果通常写到仓库的 `output/`，运行结束后复制保存：

```bash
mkdir -p "$OOD_ROOT/results/lcb_release_v6"
cp -a output/. "$OOD_ROOT/results/lcb_release_v6/"
```

保存 `release_v6`、仓库 commit、生成文件、evaluation 文件、`pass@1/pass@5` 和 timeout 参数。

## 9. BFCL v3

BFCL 官方配置使用以下模型别名：`Qwen/Qwen3-4B-Instruct-2507-FC`。

```bash
cd "$OOD_ROOT/repos/gorilla/berkeley-function-call-leaderboard"
export CUDA_VISIBLE_DEVICES=$GPU_ID
export BFCL_MODEL='Qwen/Qwen3-4B-Instruct-2507-FC'
export BFCL_LOCAL_MODEL="$MODEL_DIR"
V3_CATS=(simple_python simple_java simple_javascript parallel multiple parallel_multiple irrelevance live_simple live_multiple live_parallel live_parallel_multiple live_irrelevance live_relevance multi_turn_base multi_turn_miss_func multi_turn_miss_param multi_turn_long_context)

for CAT in "${V3_CATS[@]}"; do
  echo "===== BFCL v3: $CAT ====="
  bfcl generate --model "$BFCL_MODEL" --test-category "$CAT" \
    --backend vllm --num-gpus 1 --gpu-memory-utilization 0.90 \
    --local-model-path "$BFCL_LOCAL_MODEL" --include-input-log \
    2>&1 | tee "$OOD_ROOT/logs/bfcl_generate_${CAT}.log"
  bfcl evaluate --model "$BFCL_MODEL" --test-category "$CAT" \
    2>&1 | tee "$OOD_ROOT/logs/bfcl_evaluate_${CAT}.log"
done
```

结果：

```bash
find "$BFCL_PROJECT_ROOT" -type f \( -name '*.json' -o -name '*.csv' \) -print | sort
```

确认文件名含 `BFCL_v3_`。正式结果不要用 `--partial-eval`，除非明确写成子集结果。

## 10. 最终证据清单

```bash
cd "$OOD_ROOT"
{
  date -Is
  nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used,utilization.gpu --format=csv
  python --version
  python -m pip freeze
  git -C repos/LiveCodeBench rev-parse HEAD 2>/dev/null || true
  git -C repos/gorilla rev-parse HEAD 2>/dev/null || true
  find results logs -type f -print | sort
} | tee experiment_manifest.txt
```

最终分别报告：

- HumanEval+：EvalPlus `Base + Extra/pass@1`
- MBPP+：EvalPlus `Base + Extra/pass@1`
- LCB：`release_v6` 完整题集的 `pass@1/pass@5`
- BFCL：overall、single-turn、multi-turn 和每个 v3 类别准确率

不要把四个 benchmark 的分数简单平均；代码生成与工具调用的输入协议、执行器和指标定义不同。
