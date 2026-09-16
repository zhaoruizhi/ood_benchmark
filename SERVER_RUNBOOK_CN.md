# 服务器全流程（Qwen/Qwen3-4B-Instruct-2507）

本项目把命令拆成可重跑的阶段脚本。所有命令在服务器执行；不要停止其他用户的 GPU 进程。用户给出的 MBPP+ 重复项只做一次。

## 1. 获取代码与配置

```bash
ssh <your-server>
mkdir -p /ssd/$USER/baseline
cd /ssd/$USER/baseline
git clone https://github.com/zhaoruizhi/ood_benchmark.git
cd ood_benchmark
cp config.env.example config.env
$EDITOR config.env
```

配置至少包括：`MODEL_DIR`（已有模型目录则无需再次下载）、`OOD_ROOT`（大磁盘）、`GPU_ID`（空闲物理卡）和 `ENV_NAME`。若模型尚未下载，`MODEL_DIR` 必须是可写目录。不要把 Hugging Face token、代理密码写入 `config.env`。

## 2. GPU、环境和缓存

```bash
tmux new -s qwen3-ood
bash scripts/00_preflight.sh
bash scripts/01_setup_env.sh
```

`00_preflight.sh` 会打印 GPU/进程并检查模型文件；确认目标卡确实空闲后才继续。`01_setup_env.sh` 优先创建 Conda 环境 `$ENV_NAME`（无 Conda 时回退到 `$OOD_ROOT/venv`），安装 Transformers、vLLM、EvalPlus 等依赖并执行 `pip check`。

## 3. 下载模型和数据

```bash
bash scripts/02_download_model_and_data.sh
```

脚本使用 `hf download` 下载模型（公共仓库不需要登录），并通过 EvalPlus 官方 API 下载/缓存 HumanEval+ 与 MBPP+，打印题目数量和包版本。LiveCodeBench 和 BFCL 数据由各自官方仓库/runner 在下一阶段下载并缓存。

## 4. HumanEval+ / MBPP+

```bash
bash scripts/03_evalplus.sh
```

脚本用 vLLM greedy 解码，随后执行 `syncheck` 和 EvalPlus evaluator。优先用 Docker、`--network none` 隔离执行生成代码；没有 Docker 时会记录警告并在宿主机执行。检查 `results/evalplus` 与日志中的 `Base`、`Base + Extra`，正式主指标取 `Base + Extra/pass@1`，同时保留 Base 和原始 JSONL。

## 5. LiveCodeBench v6

```bash
bash scripts/04_livecodebench.sh
```

脚本 clone 官方 LiveCodeBench、记录 commit，若模型表缺少精确名称则加入 `Qwen/Qwen3-4B-Instruct-2507` 条目，然后运行 `codegeneration`、`release_v6`、完整题集 `--not_fast`、`--evaluate`。结果复制到 `results/lcb_release_v6`。如果 runner 的参数发生变化，先运行 `python -m lcb_runner.runner.main --help`，按当前官方参数调整；不能把默认 lite 结果标成完整 v6。

## 6. BFCL v3

```bash
bash scripts/05_bfcl.sh
```

脚本安装 Berkeley Function-Calling Leaderboard 官方仓库，使用其 `Qwen/Qwen3-4B-Instruct-2507-FC` 配置和 vLLM 本地模型路径，逐个运行 v3 的 simple、parallel、live、multi-turn 类别，再立即 evaluate。结果在 `results/bfcl` 的 `result/` 和 `score/` 中；不要使用 `--partial-eval` 作为正式结果。Java/JavaScript 类别需要服务器有 `java`、`node`，缺失时应先补齐运行时。

## 7. 证据归档与报告

```bash
bash scripts/99_manifest.sh
```

`experiment_manifest.txt` 记录时间、GPU、Python/pip、两个 harness commit 及全部结果文件。报告中逐项写明模型 revision、GPU、Python/Transformers/vLLM/EvalPlus/BFCL/LCB 版本、完整命令、timeout 和原始输出位置。四个 benchmark 协议与指标不同，不计算简单平均分。

## 8. 常见故障

- `KeyError: qwen3`：升级 `transformers>=4.51.0`，确认实际导入版本。
- OOM：重新检查 GPU 进程；降低 `VLLM_GPU_MEMORY_UTILIZATION`（如 0.80），不要抢占别人的卡。
- LCB unknown model：检查脚本对 `lm_styles.py` 的精确模型条目补丁。
- BFCL 解析失败：先单独运行 `simple_python`，查看 `include-input-log` 是否出现 `<tool_call>`；保留原始响应。
- SSH 断开：`tmux attach -t qwen3-ood`，脚本可从未完成阶段重新执行。
