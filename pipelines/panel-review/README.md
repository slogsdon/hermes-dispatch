# panel-review (prototype)

A **decorrelated two-model review panel** for high-consequence, non-interactive
review (security diffs, contracts, ToS). Two different local models review the
same artifact independently; an arbiter merges their findings into
**consensus / model-unique / disagreements**. The disagreements and unique
findings are the payload — they are where a single-model review has a blind spot.

```
python3 panel_review.py sample_vuln.py        # file
cat diff.txt | python3 panel_review.py        # stdin
PANEL_REVIEWERS=max,dense python3 panel_review.py sample_vuln.py   # override pair
```

Talks to the LiteLLM gateway (:4000) directly — no Hermes wiring needed yet.

## What the prototype proved (2026-06-20, on `sample_vuln.py`)

Run on a 4-defect-plus sample with planted SQLi, hardcoded secret, IDOR,
timing-attack, and unsalted-MD5 bugs.

1. **The mechanism works.** The arbiter cleanly split findings and surfaced a
   real severity **disagreement** (one model rated the hardcoded secret
   `medium`, the other `critical`) — exactly the signal a solo review misses.

2. **Thinking must be OFF.** `max` has a thinking channel; under a token cap its
   `<think>` block starves the JSON output (first run: **0 findings**). The
   panel forces `enable_thinking:false` on every call. Decorrelation comes from
   the *architecture*, not the reasoning mode.

3. **Pair across FAMILIES, not within.** The original idea was `max` (Qwen
   35B-A3B MoE) + `dense` (Qwen 27B dense). But they share Qwen3.6 lineage →
   correlated errors: they returned **identical findings**, differing on one
   severity. Swapping the second seat to `writing` (Gemma 26B) — a different
   family — produced a **genuine unique finding and more disagreements, and ran
   3× faster** (Gemma ~24 t/s vs dense ~6.5 t/s). Default pair is therefore
   `max,writing`. `dense` is the *worst* second seat here.

## Cost on this hardware

`max` (~21 GB) and any second large model can't co-reside on 32 GB, so the two
reviews **run sequentially with a model swap** (~1–2 min/review total). This is
strictly a batch / high-stakes tool, not interactive. The slowest second seat is
`dense` (~75s); `writing` (~24s) or `balanced` are cheaper.

## Promoting to a real pipeline

This is a standalone script. To make it a first-class Hermes pipeline, express it
as a `pipelines/*.json` fan-out (two `*-reviewer` agents → an arbiter agent) once
the reviewer/arbiter prompts here are settled. Reuses the existing
`security-reviewer` / `pr-reviewer` agent prompts as the two seats.

## Verdict on `dense`

The panel was the last plausible home for the `dense` alias. It doesn't earn the
seat (same-family → correlated, and slow). `dense` stays a manual MTP-experiment
model, not wired into any agent or panel.
