#!/usr/bin/env python3
"""How far the judge can be trusted: its verdicts against a person's, on the same pairs.

    Evals/judge_agreement.py sample <run> [<run> ...] --per-task 5     # writes the pairs to label
    Evals/judge_agreement.py score  <labels.json>                      # agreement, after labelling

`sample` draws pairs from runs that `Evals/judge.py` has judged, from repeat 0 (which the
judge saw), shuffles which answer is A, and writes `Evals/labeling/pairs.json` (what the
labelling page shows: no model names) and `Evals/labeling/key.json` (which side was which,
never published). Calls no model.

`score` reads the owner's labels (exported from the labelling page's store as
{pair_id: {"verdict": "A"|"B"|"tie"|"both_bad"}}), maps each to baseline / candidate /
tie / both_bad through the key, and compares it with the judge's combined verdict on the
same (case, repeat). It reports agreement over every pair, and over the pairs where both
the person and the judge named a winner (MT-Bench's "without tie" figure; two people agree
on about 80% of such pairs there). Calls no model.
"""
import argparse, json, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "labeling")
TASK_LABELS = {
    "insightLine": "Insight line", "weeklyReflection": "Weekly note", "onboardingNote": "Onboarding note",
    "memoryFold": "Coach memory", "progressSummary": "Progress recap", "foodSuggestions": "Food suggestions",
    "coachPrompts": "Chat chips", "checklistPlan": "Daily checklist", "coachTurn": "Vita chat",
}


def judged(run):
    files = [f for f in os.listdir(run) if f.startswith("judge-") and f.endswith(".json")]
    if not files:
        sys.exit(f"{run} has not been judged (Evals/judge.py)")
    return json.load(open(os.path.join(run, files[0])))


def records(run):
    f = next(f for f in os.listdir(run) if f.startswith("records-") and f.endswith(".jsonl"))
    return [json.loads(l) for l in open(os.path.join(run, f)) if l.strip()]


def sample(args):
    rubrics = json.load(open(os.path.join(HERE, "judge_rubrics.json")))
    rng = random.Random(args.seed)
    pairs, key = [], {}
    sys.path.insert(0, HERE)
    from judge import with_shown
    for run in args.runs:
        j = judged(run)
        recs = {(r["caseID"], r["repeatIndex"], r["candidate"]): r for r in with_shown(run, records(run))}
        pool = [v for v in j["verdicts"] if v["repeat"] == 0 and v["outcome"] is not None]
        for v in rng.sample(pool, min(args.per_task, len(pool))):
            base = recs[(v["case"], 0, j["baseline"])]
            cand = recs[(v["case"], 0, j["candidate"])]
            pid = f"{j['task']}-{v['case']}"
            baseline_is_a = rng.random() < 0.5
            a, b = (base, cand) if baseline_is_a else (cand, base)
            pairs.append({"id": pid, "task": j["task"], "taskLabel": TASK_LABELS.get(j["task"], j["task"]),
                          "rubric": rubrics[j["task"]], "given": base["given"], "a": a["judged_text"], "b": b["judged_text"]})
            key[pid] = {"run": os.path.basename(os.path.normpath(run)), "task": j["task"], "case": v["case"],
                        "repeat": 0, "baseline_is": "A" if baseline_is_a else "B",
                        "baseline": j["baseline"], "candidate": j["candidate"]}
    rng.shuffle(pairs)
    os.makedirs(OUT, exist_ok=True)
    json.dump(pairs, open(os.path.join(OUT, "pairs.json"), "w"), indent=1)
    json.dump(key, open(os.path.join(OUT, "key.json"), "w"), indent=1, sort_keys=True)
    print(f"{len(pairs)} pairs -> {OUT}/pairs.json (key in key.json)")


def side(verdict, baseline_is):
    if verdict in ("tie", "both_bad"):
        return verdict
    return "baseline" if verdict == baseline_is else "candidate"


def score(args):
    labels = json.load(open(args.labels))
    key = json.load(open(os.path.join(OUT, "key.json")))
    runs_dir = os.path.join(HERE, "runs")
    rows, by_task = [], {}
    for pid, lab in sorted(labels.items()):
        if pid not in key:
            continue
        k = key[pid]
        j = judged(os.path.join(runs_dir, k["run"]))
        v = next(x for x in j["verdicts"] if x["case"] == k["case"] and x["repeat"] == k["repeat"])
        human = side(lab["verdict"], k["baseline_is"])
        # "both_bad" and "tie" both mean no winner; they are compared as such.
        h = "none" if human in ("tie", "both_bad") else human
        m = "none" if v["outcome"] in ("tie", "both_bad") else v["outcome"]
        rows.append({"pair": pid, "task": k["task"], "person": human, "judge": v["outcome"], "agree": h == m})
        by_task.setdefault(k["task"], []).append(h == m)
    if not rows:
        sys.exit("no labelled pair matches the key")
    agree = sum(r["agree"] for r in rows)
    decisive = [r for r in rows if r["person"] not in ("tie", "both_bad") and r["judge"] not in ("tie", "both_bad")]
    agree_decisive = sum(r["agree"] for r in decisive)
    result = {"pairs": len(rows), "agree": agree, "agreement": agree / len(rows),
              "decisive_pairs": len(decisive),
              "agreement_without_ties": agree_decisive / len(decisive) if decisive else None,
              "by_task": {t: {"pairs": len(v), "agree": sum(v)} for t, v in sorted(by_task.items())},
              "rows": rows}
    json.dump(result, open(os.path.join(OUT, "agreement.json"), "w"), indent=1)
    print(f"agreement {agree}/{len(rows)} = {agree / len(rows):.0%}; "
          f"without ties {agree_decisive}/{len(decisive)}"
          + (f" = {agree_decisive / len(decisive):.0%}" if decisive else ""))
    for t, v in sorted(by_task.items()):
        print(f"  {t:18} {sum(v)}/{len(v)}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sample"); s.add_argument("runs", nargs="+")
    s.add_argument("--per-task", type=int, default=5); s.add_argument("--seed", type=int, default=7)
    c = sub.add_parser("score"); c.add_argument("labels")
    args = ap.parse_args()
    sample(args) if args.cmd == "sample" else score(args)


if __name__ == "__main__":
    main()
