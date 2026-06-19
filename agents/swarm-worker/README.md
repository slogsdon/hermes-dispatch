# swarm-worker

A single-task code grunt. Takes ONE small instruction plus the code to act on and returns only
the result — terse, no explanation, no fences. Backed by the `swarm` alias
(qwen2.5-coder:1.5b, ~1 GB), the cheapest/fastest coder on the roster. Designed to be fanned out
N-wide and run **concurrently** by `bin/swarm.py`, not used as a standalone persona.

| | |
|---|---|
| **Alias** | `swarm` (qwen2.5-coder:1.5b via LiteLLM) |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | the requested code/text only, no fences unless asked |

## Usage

```bash
# Inline (instruction + code as args):
./run.sh "Add JSDoc to this function" "function foo(x){ return x * 2; }"

# Piped (instruction, blank line, then code):
printf 'Add type annotations to all params and the return value.\n\ndef add(a, b): return a + b' | ./run.sh

# See the exact hermes command without running it:
HERMES_DRY_RUN=1 ./run.sh "..." "..."
```

You rarely call this directly. The fan-out pipelines drive it — see [`bin/swarm.py`](../../bin/swarm.py)
and [`pipelines/swarm/`](../../pipelines/swarm/):

```bash
bin/swarm.py annotate   --lang python     --file mod.py
bin/swarm.py test-stubs --framework pytest --file mod.py
echo '{"tasks":[{"id":"fn1","instruction":"Add JSDoc","code":"function foo(x){return x*2}"}]}' \
  | bin/swarm.py fanout
```

## Why this alias

`swarm` points at a 1.5B coder — fast and cheap enough to run dozens of copies in parallel for
mechanical grunt-work (annotation passes, doc stubs, test skeletons). It is **non-reasoning**, so
output is clean (no chain-of-thought to strip). It is also small enough to be wrong: treat every
result as a draft, especially anything touching logic, auth, or crypto. Route the hard, one-shot
work to `code`/`max`, and use the swarm for breadth.

## ⚠️ Caveat

A 1.5B model produces plausible-but-sometimes-broken code. The swarm is for *volume* of
low-stakes transformations, not correctness-critical work. Review or downstream-verify its output
(e.g. run the annotated/stubbed result through `pr-reviewer` or your test suite).

## Tuning

- Sampling (`temperature: 0.1`, `max_tokens: 300`) is documented in `agent.yaml` but enforced on
  the `swarm` LiteLLM alias — the hermes CLI takes no sampling flags.
- Want a slightly stronger worker? Point `alias` at `code`. You trade throughput for quality.
