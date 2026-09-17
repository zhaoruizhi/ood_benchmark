# HumanEval+ / MBPP+：T=1.0、Top-p=0.8、38K、TP=4

本方案继续使用四个独立 seed，各生成一个样本并计算任务级 `pass@1`，最后报告四次结果的均值与样本标准差。`38K` 和 `40K` 均按 `K=1024` 解释：

- temperature：`1.0`
- top-p：`0.8`
- top-k：`-1`（不启用 top-k 截断）
- max new tokens：`38912`
- max model length：`40960`
- tensor parallel：`4`
- 默认 seed：`20260917,20260918,20260919,20260920`

## 1. 更新代码并进入环境

在没有其他进程修改此 worktree 时执行：

```bash
cd /ssd/tlwang/baseline/ood_benchmark_avg4
git pull --ff-only origin main
source /ssd/tlwang/baseline/ood_benchmark/venv/bin/activate
```

## 2. 建立本次实验专用配置

不要覆盖此前 temperature=0.2 的结果。复制现有配置并只修改 GPU/TP：

```bash
cd /ssd/tlwang/baseline/ood_benchmark_avg4
cp config.env config.evalplus_t1_p08_38k_tp4.env

sed -i -E \
  -e 's/^GPU_ID=.*/GPU_ID=4,5,6,7/' \
  -e 's/^TP_SIZE=.*/TP_SIZE=4/' \
  config.evalplus_t1_p08_38k_tp4.env

grep -E '^(MODEL_DIR|OOD_ROOT|GPU_ID|TP_SIZE|VLLM_USE_V1|NCCL_NVLS_ENABLE)=' \
  config.evalplus_t1_p08_38k_tp4.env
```

预期至少包含：

```text
GPU_ID=4,5,6,7
TP_SIZE=4
VLLM_USE_V1=0
NCCL_NVLS_ENABLE=0
```

`MODEL_DIR` 必须仍指向要评测的 checkpoint。

## 3. GPU 和模型预检

```bash
CONFIG_FILE="$PWD/config.evalplus_t1_p08_38k_tp4.env" \
bash scripts/00_preflight.sh
```

预检会在任意选中 GPU 显存使用超过 1024 MiB 时停止。不要跳过该检查或结束其他用户的进程。

## 4. TP=4、40K 上下文初始化测试

先只初始化模型和生成一个短答案，确认 NCCL、TP=4 和 40K 上下文可用：

```bash
CONFIG_FILE="$PWD/config.evalplus_t1_p08_38k_tp4.env" \
VLLM_SMOKE_MAX_MODEL_LEN=40960 \
bash scripts/02b_model_smoke.sh \
2>&1 | tee /ssd/tlwang/baseline/ood_benchmark/logs/tp4_ctx40960_smoke.log
```

日志必须出现 `visible GPUs = 4`、`tensor_parallel_size = 4` 和成功生成结果。若初始化失败，不要启动完整 benchmark。

## 5. 正式运行四次采样

建议在 tmux 中执行。结果目录名包含所有关键采样设置，避免读到旧缓存：

```bash
cd /ssd/tlwang/baseline/ood_benchmark_avg4
source /ssd/tlwang/baseline/ood_benchmark/venv/bin/activate

export RUN_ROOT=/ssd/tlwang/baseline/ood_benchmark/results/evalplus_avg4_base_t1_p08_k-1_new38912_ctx40960_tp4

CONFIG_FILE="$PWD/config.evalplus_t1_p08_38k_tp4.env" \
AVG_ROOT="$RUN_ROOT" \
ALLOW_HOST_EVAL=1 \
bash scripts/07_evalplus_avg4_t1_p08_38k_tp4.sh \
2>&1 | tee "$RUN_ROOT.launch.log"
```

脚本会把完整配置写入 `$RUN_ROOT/run_config.json`。如果目录中已有不同配置，脚本会拒绝继续，避免混合结果。

## 6. 监控

另开一个 tmux 窗口：

```bash
watch -n 2 nvidia-smi
```

确认物理 GPU 4、5、6、7 都存在同一组 vLLM worker。四张卡同时被占用表示 TP=4 生效。

查看当前进度：

```bash
tail -f "$RUN_ROOT/logs/humaneval_avg4_seed_20260917_codegen.log"
```

## 7. 检查结果

```bash
cat "$RUN_ROOT/run_config.json"
cat "$RUN_ROOT/avg4_summary.json"
cat "$RUN_ROOT/logs/evalplus_avg4_summary.log"
```

检查任务数量：HumanEval 应为 164，MBPP 应为 378。正式报告使用 `plus_pass_at_1_mean`；`base_pass_at_1_mean` 作为原始测试集参考。

## 8. 中断后继续

使用完全相同的 `CONFIG_FILE`、`AVG_ROOT` 和命令重新执行。EvalPlus 会复用该结果目录中已经生成完整的样本，未完成的 seed/dataset 会继续生成。不要更改已有运行目录中的采样设置。
