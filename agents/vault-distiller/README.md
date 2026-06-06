# vault-distiller

Distills a long, messy note into **atomic concepts + suggested `[[wikilinks]]` + tags +
open threads**, the structuring work behind a healthy Obsidian knowledge graph. Output
drops straight into the vault knowledge skills (`bloom`, `connect`, `emerge`, `backlinks`).

| | |
|---|---|
| **Alias** | `quality` → `qwen3.6:35b-mlx` (21.9 GB) |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | 4 fixed Markdown sections |

## Usage

Feed note **content** in, this agent never reads the vault itself (vault access goes
through the `obsidian` skill/CLI per Shane's rules):

```bash
# From the obsidian CLI:
./run.sh "$(obsidian read file='Minimal Agents in Hermes (agent harness)')"

# From a piped file:
cat note.md | ./run.sh
```

## Why this alias

This is the one agent that earns `quality` (qwen3.6:35b-mlx). The brief's rule: reserve
the 22 GB model for the **genuinely hard, long-context step** and use cheap models
elsewhere. Note synthesis, collapsing a sprawling note into durable atomic claims and
inferring the right links, is exactly that step. It fits *alone* on 32 GB; don't expect
to co-resident it with another large model.

## Caveats

- `qwen3.6` is MoE/long-context; if you feed a very long note and see swapping, lower the
  alias's `num_ctx` in the LiteLLM config rather than here.
- Inferred links/concepts are marked `(inferred)`, review before committing to the graph.
- `parse_last_line` is **off**: the full four-section Markdown block is the deliverable.
