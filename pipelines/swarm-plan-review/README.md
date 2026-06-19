# swarm-plan-review — plan → swarm → review

A three-stage swarm pipeline that bookends the parallel [`swarm`](../swarm/) fan-out with a
capable "smart" model on both ends. One free-text task goes in; one synthesized result comes out.

```
--task ──▶  PLAN (smart model)  ──▶  SWARM (qwen2.5-coder:1.5b ×N)  ──▶  REVIEW (smart model)  ──▶  JSON
            decompose into a            run every task in parallel        consolidate all outputs
            JSON task list              (bin/swarm.py fanout engine)      into one final result
```

1. **Plan** — the task description (plus any `--files`) goes to the smart model (the `max` alias
   by default), which returns a JSON array of independent `{id, task, context}` subtasks, one per
   worker.
2. **Swarm** — every planned task is fanned out to the cheap `swarm` workers
   (qwen2.5-coder:1.5b) through the existing [`bin/swarm.py`](../../bin/swarm.py) `fanout()`
   engine (`ThreadPoolExecutor`, default 8-wide).
3. **Review** — the original task plus all per-worker outputs go back to the smart model for a
   consolidation pass that produces the final synthesized result.

## Why it lives in `bin/swarm.py`, not as a `*.json` pipeline

Same reason as the other [swarm pipelines](../swarm/README.md#why-these-arent-json-pipelines):
the linear runner ([`lib/orchestrate.sh`](../../lib/orchestrate.sh)) threads **one** key from step
to step and runs steps **sequentially** — it can't fan a *list* out to many concurrent workers.
This pipeline reuses the same `fanout()` engine, so it's a subcommand of `bin/swarm.py` rather than
a duplicated handler. The plan and review stages call LiteLLM's OpenAI-compatible endpoint
(`http://127.0.0.1:4000`) directly — they want a long-context reasoner, not the minimal
stdin→stdout worker path.

## Usage

```bash
# Decompose, fan out, and consolidate a single task
bin/swarm.py plan-swarm-review --task "Refactor the auth module for testability"

# Give the planner files as context (their contents are inlined into the plan prompt)
bin/swarm.py --workers 5 plan-swarm-review \
  --task "Add type annotations across these modules" \
  --files src/a.py src/b.py

# Use a different smart-model alias for plan + review
bin/swarm.py plan-swarm-review --task "..." --model reasoning
```

`--workers N` (the global flag, before the subcommand) caps swarm concurrency.

## Output

Clean JSON on **stdout** (progress goes to **stderr**, so stdout stays pipe-safe):

```json
{
  "task":   "the original --task text",
  "model":  "max",
  "plan":   [{ "id", "task", "context" }],
  "swarm":  [{ "id", "result", "tokens_used" }],
  "review": "the final synthesized result"
}
```

`tokens_used` on each swarm result is an estimate (~len/4) — the hermes CLI surfaces no usage
counts. Pull the final answer from `.review`; `.plan` and `.swarm` are kept for inspection.

## Knobs

| Env / flag | Default | Effect |
|------------|---------|--------|
| `--model` | `max` | smart-model alias for the plan + review stages |
| `SMART_MODEL` | `max` | same, via env (overridden by `--model`) |
| `--workers N` | 8 | swarm fan-out concurrency (global flag; `SWARM_MAX_WORKERS` also works) |
| `LITELLM_BASE_URL` | `http://127.0.0.1:4000` | LiteLLM endpoint for plan/review |
| `SMART_TIMEOUT` | 300 | plan/review HTTP timeout (seconds) |
| `SWARM_TIMEOUT` | 180 | per-worker timeout (seconds) |
| `HERMES_DRY_RUN=1` | — | stub the plan/review model calls **and** make workers print their composed hermes command — exercises the whole three-stage pipeline with no GPU/model cost |

The LiteLLM key is read from `LITELLM_MASTER_KEY` / `CC_LITELLM_MASTER_KEY` in the environment,
then from `~/.command-center/env`, then `~/.hermes/.env`.

## ⚠️ Caveat

The swarm workers are a 1.5B model — plausible-but-sometimes-broken code. The review stage cleans
up and reconciles, but it is not a correctness guarantee. Treat the final result as a strong draft
and verify downstream (run it through your test suite or `pr-reviewer`).
