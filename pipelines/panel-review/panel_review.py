#!/usr/bin/env python3
"""panel-review — decorrelated two-model review panel (PROTOTYPE).

Runs the SAME review over two architecturally different local models:
  - `max`   : Qwen3.6-35B-A3B  (MoE, thinking ON)
  - `dense` : Qwen3.6-27B      (dense, thinking OFF, MTP)

Their errors are decorrelated (MoE routing vs dense), so an arbiter pass over
both finding-sets splits them into consensus / model-unique / disagreements.
The DISAGREEMENTS are the payload: findings only one architecture saw, i.e.
where a single-model review would have a blind spot.

Usage:
  python3 panel_review.py <file>            # review a file (diff, source, contract…)
  cat diff.txt | python3 panel_review.py    # or from stdin

Calls the LiteLLM gateway (:4000) directly — it already serves `max` and `dense`.
This is a prototype; promote to a real Hermes pipeline once the shape is settled.
"""
import json, os, re, sys, time, urllib.request

GATEWAY = "http://localhost:4000/v1/chat/completions"
ENV     = os.path.expanduser("~/Code/otel-local-ai/.env")
# Two panelists + an arbiter. Override the pair to taste, e.g.:
#   PANEL_REVIEWERS=max,writing   (cross-FAMILY: Qwen MoE + Gemma — more decorrelated)
#   PANEL_REVIEWERS=max,dense     (same-family Qwen MoE + dense — weak decorrelation)
REVIEWERS = os.environ.get("PANEL_REVIEWERS", "max,writing").split(",")
ARBITER   = os.environ.get("PANEL_ARBITER", "max")

def key():
    for line in open(ENV):
        if line.startswith("LITELLM_MASTER_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit("no LITELLM_MASTER_KEY in " + ENV)

K = key()

REVIEW_PROMPT = """You are a senior security + correctness reviewer. Review the ARTIFACT below.
Report concrete defects only: security holes, correctness bugs, data-loss/race risks, auth gaps.
Be terse. At most 6 findings. Output ONLY a JSON array, no prose, no markdown fence:
[{"severity":"critical|high|medium|low","location":"<func/line/area>","issue":"<one line>","why":"<one line impact>"}]

ARTIFACT:
```
%s
```"""

ARBITER_PROMPT = """Two independent reviewers (A and B) reviewed the same artifact. Their findings:

A (%s):
%s

B (%s):
%s

Merge them semantically (the SAME defect worded differently = one item). Output ONLY this JSON, no prose:
{"consensus":[{"issue":"","severity":""}],
 "only_A":[{"issue":"","severity":""}],
 "only_B":[{"issue":"","severity":""}],
 "disagreements":[{"item":"","note":"why the two reviews differ / which to trust"}]}
'consensus' = both found it. 'only_A'/'only_B' = one architecture's blind spot the other covered. 'disagreements' = contradictions or severity splits worth a human's eye."""

def call(model, prompt, max_tokens=1100):
    # Thinking OFF: this is a structured-JSON task. `max` (thinking ON by default)
    # otherwise spends the token budget in <think> and starves the JSON. The panel's
    # decorrelation comes from the ARCHITECTURE (MoE vs dense), not from reasoning mode.
    payload = {
        "model": model, "temperature": 0, "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
        "extra_body": {"chat_template_kwargs": {"enable_thinking": False}},
    }
    body = json.dumps(payload).encode()
    req = urllib.request.Request(GATEWAY, data=body,
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + K})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=400) as r:
        d = json.load(r)
    txt = d["choices"][0]["message"]["content"]
    return txt, time.time() - t0

def strip_think(s):
    return re.sub(r"<think>.*?</think>", "", s, flags=re.S).strip()

def extract_json(s):
    s = strip_think(s)
    # last [...] or {...} block
    for open_c, close_c in (("[", "]"), ("{", "}")):
        i, j = s.find(open_c), s.rfind(close_c)
        if i != -1 and j > i:
            try: return json.loads(s[i:j+1])
            except Exception: pass
    return None

def review(model, artifact):
    raw, dur = call(model, REVIEW_PROMPT % artifact)
    findings = extract_json(raw) or []
    if not findings:
        print(f"  ! {model} returned no parseable findings; raw head:\n    "
              + strip_think(raw)[:200].replace("\n", "\n    "), flush=True)
    return {"model": model, "dur": dur, "findings": findings, "raw": raw}

def main():
    artifact = (open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read())
    if not artifact.strip():
        sys.exit("empty artifact")
    print(f"panel-review: {len(artifact)} chars over {REVIEWERS} (arbiter={ARBITER})\n", flush=True)

    # SEQUENTIAL by design: max (~21GB) and dense (~17GB) can't co-reside on 32GB,
    # so concurrency would only thrash llama-swap. Each model pays a load/swap here.
    results = [review(m, artifact) for m in REVIEWERS]

    for r in results:
        print(f"  {r['model']:6s}: {len(r['findings'])} findings in {r['dur']:.0f}s", flush=True)
        for f in r["findings"]:
            if isinstance(f, dict):
                print(f"      [{f.get('severity','?'):8s}] {f.get('location','')}: {f.get('issue','')}")
    print(flush=True)

    A, B = results[0], results[1]
    arb_raw, arb_dur = call(ARBITER, ARBITER_PROMPT % (
        A["model"], json.dumps(A["findings"]), B["model"], json.dumps(B["findings"])))
    merged = extract_json(arb_raw) or {}

    def show(title, items, fmt):
        print(f"━━ {title} ({len(items)}) ━━")
        for it in items:
            print("   " + fmt(it))
        if not items: print("   —")
        print()

    print(f"═══ PANEL VERDICT (arbiter {arb_dur:.0f}s) ═══\n")
    show("CONSENSUS — both architectures agree", merged.get("consensus", []),
         lambda it: f"[{it.get('severity','?')}] {it.get('issue','')}")
    show(f"ONLY {A['model']} — dense blind spot", merged.get("only_A", []),
         lambda it: f"[{it.get('severity','?')}] {it.get('issue','')}")
    show(f"ONLY {B['model']} — MoE blind spot", merged.get("only_B", []),
         lambda it: f"[{it.get('severity','?')}] {it.get('issue','')}")
    show("DISAGREEMENTS — human eyes here", merged.get("disagreements", []),
         lambda it: f"{it.get('item','')} — {it.get('note','')}")

if __name__ == "__main__":
    main()
