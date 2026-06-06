# gtm-planner

Turns a product/feature brief into a **decision-ready go-to-market plan**: positioning,
ranked segments, channels, launch sequence, messaging pillars, metrics, and risks. The
strategy half of the GTM pair; `gtm-executor` writes the assets from it.

| | |
|---|---|
| **Alias** | `quality` → `qwen3.6:35b-mlx` (21.9 GB) |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | 7 fixed Markdown sections |

## Usage

```bash
cat feature-brief.md | ./run.sh

./run.sh "Brief: hermes-agents, a free local-LLM agent toolkit for indie devs, \
runs on a 32 GB Mac Mini, no API costs. Target: developers tired of cloud bills."

# Hand the plan straight to the executor:
cat brief.md | ./run.sh | ./../gtm-executor/run.sh
```

## Why this alias

GTM planning is genuine reasoning, segmentation, sequencing, trade-offs, so it earns
`quality` (qwen3.6:35b-mlx), the strongest local model, which also routes its thinking to a
separate channel (clean plan, no `strip_think` needed).

> **Why not `analyze` (deepseek-r1)?** That was the obvious "reasoning slot" pick, but
> deepseek-r1 is **incompatible with Hermes**: Hermes always sends a non-empty tools array
> (even with `-t ""`), and deepseek-r1's Ollama template rejects it
> (`does not support tools`). It's reachable only via raw LiteLLM/Ollama, not the harness.
> See the top-level README's tool-compatibility note.

## Tuning

- Shares `quality` (22 GB) with `vault-distiller` and `lead-designer`, fine, since they run
  one at a time; just don't co-resident two large models.
- For a lighter, faster plan, switch `alias: write` (gpt-oss:20b), also tool-compatible,
  less judgment.
