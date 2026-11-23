"""Ask each Claude model, once per setting, how it treats the `thinking` field under a small cap.

    ANTHROPIC_API_KEY=... python3 Evals/probe_anthropic_thinking.py \
        "claude-haiku-5-5,claude-sonnet-5-5,claude-sonnet-5,claude-haiku-4-5-20251001" "80,420"

One request per model, setting and cap (24 for the line above, well under a cent). Prints
the HTTP status and message of a rejected setting, or the stop reason, block types, output
tokens and reported thinking tokens of an accepted one. The key is read from the
environment and never printed. `AnthropicModelProfile` in the app is the table this
confirms (docs/EVAL_REPORT.md section 25); run it again when a model is added.
"""
import json, os, sys, urllib.request, urllib.error
key = os.environ["ANTHROPIC_API_KEY"]
system = "You are a warm health coach. Reply with one short encouraging sentence, under 20 words. No preamble."
user = "Facts: 9-day logging streak. Protein 96 g of 120 g yesterday. Water goal met 5 of the last 7 days."
models = sys.argv[1].split(",")
configs = {"none": None, "disabled": {"type": "disabled"}, "between_tools": {"type": "between_tools"}}
caps = [int(c) for c in sys.argv[2].split(",")]
for model in models:
    for name, thinking in configs.items():
        for cap in caps:
            body = {"model": model, "max_tokens": cap, "system": system, "messages": [{"role": "user", "content": user}]}
            if thinking: body["thinking"] = thinking
            req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=json.dumps(body).encode(),
                headers={"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=90) as r: d = json.load(r); status = 200
            except urllib.error.HTTPError as e:
                status = e.code; d = json.loads(e.read().decode() or "{}")
            if status != 200:
                print(f"{model:28s} thinking={name:14s} cap={cap:4d} HTTP {status}: {(d.get('error') or {}).get('message', '')[:150]}")
                continue
            blocks = [b.get("type") for b in d.get("content", [])]
            text = "".join(b.get("text", "") for b in d.get("content", []) if b.get("type") == "text")
            u = d.get("usage", {})
            print(f"{model:28s} thinking={name:14s} cap={cap:4d} stop={d.get('stop_reason'):11s} blocks={blocks} out={u.get('output_tokens')} details={u.get('output_tokens_details')} text={text[:70]!r}")
