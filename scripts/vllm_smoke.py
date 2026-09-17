#!/usr/bin/env python3
import os

from vllm import LLM, SamplingParams


def main() -> None:
    model_dir = os.environ["MODEL_DIR"]
    tp_size = int(os.environ.get("TP_SIZE", "1"))
    gpu_memory_utilization = float(
        os.environ.get("SMOKE_GPU_MEMORY_UTILIZATION", "0.20")
    )
    llm = LLM(
        model=model_dir,
        tensor_parallel_size=tp_size,
        max_model_len=2048,
        gpu_memory_utilization=gpu_memory_utilization,
        trust_remote_code=True,
    )
    outputs = llm.generate(
        ["Write one Python function add(a, b) that returns a+b. Return code only."],
        SamplingParams(temperature=0.0, max_tokens=64),
    )
    text = outputs[0].outputs[0].text.strip()
    if not text:
        raise RuntimeError("vLLM smoke produced empty output")
    print(text)


if __name__ == "__main__":
    main()
