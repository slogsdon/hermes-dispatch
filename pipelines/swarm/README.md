# swarm pipelines — parallelized coding grunt-work

Three fan-out pipelines that spread mechanical code transforms across many concurrent
[`swarm-worker`](../../agents/swarm-worker/) agents (`swarm` alias → qwen2.5-coder:1.5b).
For volume of low-stakes edits — annotation passes, doc/test stubs, batch one-shot transforms —
not for correctness-critical work.

## Why these aren't `*.json` pipelines

The linear runner ([`bin/run-pipeline.sh`](../../bin/run-pipeline.sh) +
[`lib/orchestrate.sh`](../../lib/orchestrate.sh)) threads **one** named key from step to step
and runs steps **sequentially** — its step types (`agent` / `gate` / `tool` / `test-loop`) have
no notion of fanning a *list* of inputs out to many workers at once. The swarm pipelines take a
list and run it N-wide, so they live in a dedicated handler,
[`bin/swarm.py`](../../bin/swarm.py), which does the fan-out with a `ThreadPoolExecutor` (each
worker is an independent `swarm-worker` subprocess). Same project split — agents stay pure
stdin→stdout shell wrappers, the orchestration layer owns concurrency — just with the
parallelism the linear runner lacks.

## The three pipelines

| Pipeline | Input | Output |
|----------|-------|--------|
| `fanout` | JSON list of `{id, instruction, code}` tasks | `[{id, result, tokens_used}]` |
| `annotate` | code + `--lang python\|typescript\|php` | annotated functions, one result per function |
| `test-stubs` | code + `--framework jest\|pytest\|phpunit` | test stubs, one result per function |

`annotate` / `test-stubs` split the input into per-function units and fan each unit out as its
own task. If the input can't be split, the whole thing is sent as a single unit.

## Usage

```bash
# Generic fan-out
echo '{"tasks":[
  {"id":"fn1","instruction":"Add JSDoc","code":"function foo(x){return x*2}"},
  {"id":"fn2","instruction":"Add JSDoc","code":"function bar(y){return y+1}"}
]}' | bin/swarm.py fanout

# Type-annotation pass over a file (one worker per function)
bin/swarm.py annotate --lang python --file mymodule.py

# Test stubs from piped code
cat utils.ts | bin/swarm.py test-stubs --framework jest
```

Output is JSON: `[{ "id", "result", "tokens_used" }]`, in input order. `tokens_used` is an
estimate (~len/4) — the hermes CLI surfaces no usage counts.

## Knobs

| Env | Default | Effect |
|-----|---------|--------|
| `SWARM_MAX_WORKERS` | 8 | concurrency cap (also `--workers N`) |
| `SWARM_TIMEOUT` | 180 | per-worker timeout (seconds) |
| `HERMES_DRY_RUN=1` | — | workers print their composed hermes command instead of calling a model |

## ⚠️ Caveat

A 1.5B model writes plausible-but-sometimes-broken code. Treat every result as a draft and
verify downstream (run the annotated/stubbed output through your test suite or `pr-reviewer`).
