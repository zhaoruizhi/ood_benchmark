#!/usr/bin/env python3
"""Aggregate four independently seeded EvalPlus pass@1 evaluations."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def score(path: Path) -> dict[str, float | int]:
    from evalplus.eval import PASS

    payload = json.loads(path.read_text())
    rows = list(payload["eval"].values())
    if not rows:
        raise ValueError(f"no task results in {path}")
    base = sum(row[0]["base_status"] == PASS for row in rows) / len(rows)
    plus = sum(
        row[0]["base_status"] == row[0]["plus_status"] == PASS for row in rows
    ) / len(rows)
    return {"tasks": len(rows), "base_pass_at_1": base, "plus_pass_at_1": plus}


def mean_std(values: list[float]) -> tuple[float, float]:
    mean = sum(values) / len(values)
    if len(values) == 1:
        return mean, 0.0
    variance = sum((value - mean) ** 2 for value in values) / (len(values) - 1)
    return mean, math.sqrt(variance)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--seeds", required=True, help="comma-separated seed list")
    args = parser.parse_args()
    seeds = [seed.strip() for seed in args.seeds.split(",") if seed.strip()]
    if len(seeds) != 4:
        raise SystemExit("avg@4 requires exactly four seeds")

    summary: dict[str, list[dict[str, float | int | str]]] = {"humaneval": [], "mbpp": []}
    for seed in seeds:
        for dataset in summary:
            matches = sorted(
                p
                for p in (args.root / f"seed_{seed}" / dataset).glob("*_eval_results.json")
                if ".raw_" not in p.name
            )
            if len(matches) != 1:
                raise SystemExit(
                    f"expected exactly one evaluation file for {dataset}, seed={seed}; found {matches}"
                )
            summary[dataset].append({"seed": seed, **score(matches[0])})

    report: dict[str, object] = {"seeds": seeds, "datasets": {}}
    for dataset, runs in summary.items():
        base_mean, base_std = mean_std([float(r["base_pass_at_1"]) for r in runs])
        plus_mean, plus_std = mean_std([float(r["plus_pass_at_1"]) for r in runs])
        report["datasets"][dataset] = {
            "runs": runs,
            "base_pass_at_1_mean": base_mean,
            "base_pass_at_1_sample_std": base_std,
            "plus_pass_at_1_mean": plus_mean,
            "plus_pass_at_1_sample_std": plus_std,
        }
        print(
            f"{dataset}+: avg@4 pass@1 = {plus_mean:.4f} ± {plus_std:.4f} "
            f"({plus_mean * 100:.2f}% ± {plus_std * 100:.2f}%)"
        )
    output = args.root / "avg4_summary.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
