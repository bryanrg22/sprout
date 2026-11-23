#!/usr/bin/env python3
"""Turn one run's records into the comparison table (summary.md + summary.json).

    python3 Evals/summarize.py Evals/runs/<run-id>

Per candidate: how many attempts returned something usable, the pass rate with a
95% Wilson interval and its spread across repeats, the mean of every named score,
latency, tokens, and the cost from Evals/prices.json (blank when a model has no
verified price there, never estimated).
"""
import glob, json, math, os, statistics, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))


def wilson(passed, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = passed / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def percentile(values, q):
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(q * (len(ordered) - 1))))]


def cost_usd(record, prices):
    price = prices.get("models", {}).get(f"{record['provider']}:{record['model']}")
    if not price:
        return None
    return (record["uncachedInputTokens"] * price["input"]
            + record["cacheReadTokens"] * price.get("cache_read", price["input"])
            + record["cacheWriteTokens"] * price.get("cache_write", price["input"])
            + record["outputTokens"] * price["output"]) / 1_000_000


def main():
    run = sys.argv[1]
    prices = json.load(open(os.path.join(HERE, "prices.json")))
    records = []
    for path in sorted(glob.glob(os.path.join(run, "records-*.jsonl"))):
        records += [json.loads(line) for line in open(path) if line.strip()]
    if not records:
        print("no records in", run)
        return 1

    by_task = defaultdict(list)
    for r in records:
        by_task[(r["task"], r["dataset"])].append(r)

    md, out = [], {"run": os.path.basename(run.rstrip("/")), "tasks": []}
    for (task, dataset), rows in sorted(by_task.items()):
        candidates = sorted({r["candidate"] for r in rows})
        score_names = sorted({k for r in rows for k in r["scores"]})
        cases = sorted({r["caseID"] for r in rows})
        md.append(f"## {task} on `{dataset}` ({len(cases)} cases)\n")
        md.append("| candidate | attempts | usable | pass | 95% CI | per-repeat pass | p50 s | p95 s | "
                  "in (uncached / cached) | out | $ / call | $ / 1k calls |")
        md.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
        task_out = {"task": task, "dataset": dataset, "cases": len(cases), "candidates": []}
        for c in candidates:
            mine = [r for r in rows if r["candidate"] == c]
            n = len(mine)
            usable = sum(r["ok"] for r in mine)
            passed = sum(r["pass"] for r in mine)
            lo, hi = wilson(passed, n)
            by_repeat = defaultdict(list)
            for r in mine:
                by_repeat[r["repeatIndex"]].append(r["pass"])
            per_repeat = [sum(v) / len(v) for _, v in sorted(by_repeat.items())]
            lat = [r["latencyMs"] / 1000 for r in mine if r["ok"]]
            costs = [x for x in (cost_usd(r, prices) for r in mine) if x is not None]
            mean = lambda key: statistics.mean(r[key] for r in mine) if mine else 0
            cost = statistics.mean(costs) if costs and len(costs) == n else None
            scores = {k: statistics.mean(r["scores"][k] for r in mine if k in r["scores"])
                      for k in score_names if any(k in r["scores"] for r in mine)}
            md.append("| `{}` | {} | {:.0%} | **{:.0%}** | {:.0%}–{:.0%} | {} | {:.1f} | {:.1f} | {:.0f} / {:.0f} | {:.0f} | {} | {} |".format(
                c, n, usable / n, passed / n, lo, hi,
                " ".join(f"{p:.0%}" for p in per_repeat),
                percentile(lat, 0.5), percentile(lat, 0.95),
                mean("uncachedInputTokens"), mean("cacheReadTokens"), mean("outputTokens"),
                f"{cost:.5f}" if cost is not None else "",
                f"{cost * 1000:.2f}" if cost is not None else ""))
            task_out["candidates"].append({
                "candidate": c, "attempts": n, "usable": usable, "passed": passed,
                "pass_rate": passed / n, "ci95": [lo, hi], "per_repeat_pass": per_repeat,
                "latency_p50_s": percentile(lat, 0.5), "latency_p95_s": percentile(lat, 0.95),
                "mean_uncached_input_tokens": mean("uncachedInputTokens"),
                "mean_cache_read_tokens": mean("cacheReadTokens"),
                "mean_cache_write_tokens": mean("cacheWriteTokens"),
                "mean_output_tokens": mean("outputTokens"),
                "mean_cost_usd": cost, "scores": scores,
                "errors": sorted({r["error"] for r in mine if r.get("error")})[:5],
            })

        md.append("\n**Mean of each score** (0–1 unless the name says otherwise)\n")
        md.append("| score | " + " | ".join(f"`{c}`" for c in candidates) + " |")
        md.append("|---|" + "---|" * len(candidates))
        for k in score_names:
            cells = []
            for c in candidates:
                vals = [r["scores"][k] for r in rows if r["candidate"] == c and k in r["scores"]]
                cells.append(f"{statistics.mean(vals):.3f}" if vals else "")
            md.append(f"| {k} | " + " | ".join(cells) + " |")

        md.append("\n**Cases not passed every time** (passes / attempts)\n")
        md.append("| case | " + " | ".join(f"`{c}`" for c in candidates) + " |")
        md.append("|---|" + "---|" * len(candidates))
        any_fail = False
        for case in cases:
            cells, failed = [], False
            for c in candidates:
                mine = [r for r in rows if r["candidate"] == c and r["caseID"] == case]
                p = sum(r["pass"] for r in mine)
                failed |= p < len(mine)
                cells.append(f"{p}/{len(mine)}")
            if failed:
                any_fail = True
                md.append(f"| {case} | " + " | ".join(cells) + " |")
        if not any_fail:
            md.append("| (none) |" + " |" * len(candidates))

        errors = sorted({(r["candidate"], r["error"]) for r in rows if r.get("error")})
        if errors:
            md.append("\n**Errors**\n")
            for c, e in errors[:20]:
                md.append(f"- `{c}`: {e}")
        md.append("")
        out["tasks"].append(task_out)

    open(os.path.join(run, "summary.md"), "w").write("\n".join(md) + "\n")
    json.dump(out, open(os.path.join(run, "summary.json"), "w"), indent=1)
    print("\n".join(md))
    return 0


if __name__ == "__main__":
    sys.exit(main())
