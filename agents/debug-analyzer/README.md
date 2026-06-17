# debug-analyzer

The **systematic-debugging** stage as a local agent — invoked "when blocked" during **Step 4
(Build)** (local counterpart to `superpowers:systematic-debugging`). Given a symptom (error,
stack trace, failing test) and any code, it localizes the root cause: ranked, **falsifiable**
hypotheses and the single cheapest next probe. It does not fix-spray.

| | |
|---|---|
| **Alias** | `reasoning` → `qwen3.6:35b-mlx` (21.9 GB) |
| **Tools** | none |
| **Turns** | 4 (one-shot, or a short repro-detail clarify) |
| **Output** | `## Symptom` / `## Hypotheses` / `## Next Diagnostic` / `## Likely Fix & Guard` |

## Usage

```bash
pytest 2>&1                       | ./run.sh
./run.sh "$(cat error.log) --- $(cat suspect.py)"
```

## Why this alias

Reasoning from a trace to falsifiable hypotheses and choosing the highest-information probe is
exactly what the dedicated reasoning slot (`reasoning`/qwen3.6:35b-mlx, today the same model
as `max`) is for. The prompt
forces every hypothesis to carry its own kill-test (no guess without a falsification step),
ranks by likelihood not ease of fix, prefers the boring common cause, and ends with a
regression guard so the bug can't silently return.
