# Qwen3-4B OOD Benchmark

针对 `Qwen/Qwen3-4B-Instruct-2507` 的可复现跨域评测工程，包含 EvalPlus（HumanEval+、MBPP+）、LiveCodeBench `release_v6` 和 BFCL v3。用户列表中的 MBPP+ 重复项只运行一次。

## 快速开始

```bash
git clone https://github.com/zhaoruizhi/ood_benchmark.git
cd ood_benchmark
cp config.env.example config.env
vi config.env
bash scripts/00_preflight.sh
bash scripts/01_setup_env.sh  # 创建 EvalPlus、LCB、BFCL v3 三个隔离环境
bash scripts/02_download_model_and_data.sh
bash scripts/02b_model_smoke.sh
bash scripts/03_evalplus.sh
bash scripts/04_livecodebench.sh
bash scripts/05_bfcl.sh
bash scripts/99_manifest.sh
```

建议在 `tmux` 中执行，并保留 `$OOD_ROOT` 下的所有原始输出、评测文件、日志和版本信息。详见 [`SERVER_RUNBOOK_CN.md`](SERVER_RUNBOOK_CN.md)。

HumanEval+/MBPP+ 使用 `temperature=1.0`、`top-p=0.8`、`top-k=-1`、38K 输出、40K 上下文和 TP=4 的完整步骤见 [`EVALPLUS_T1_P08_38K_TP4_CN.md`](EVALPLUS_T1_P08_38K_TP4_CN.md)。其中 K 按 1024 计算。

不要复用旧版单一 `venv`：三个 harness 的 Tree-sitter、Mistral 和其他传递依赖互不兼容。默认使用物理 GPU 4、单卡 TP=1；每次运行前仍须重新执行预检。EvalPlus/LCB 会执行模型生成代码，没有容器隔离时不得在共享宿主机上进行正式评分。

HumanEval+/MBPP+ 主指标是 `Base + Extra/pass@1`；LCB 必须注明 `release_v6`、完整题集（`--not_fast`）并报告 `pass@1/pass@5`；BFCL 报告 v3 类别、single-turn/multi-turn 和 overall。四个 benchmark 的协议与指标不同，不计算简单平均分。
