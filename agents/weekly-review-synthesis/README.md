# weekly-review-synthesis

Feeds on a week of daily notes (or a brain dump) and produces a candid Obsidian weekly
review: **top 3 wins**, **top 3 things that didn't go as planned**, **energy patterns**
(what drained vs energized), and **one clear focus for next week**. Drops straight into a
weekly-note template.

| | |
|---|---|
| **Alias** | `quality` → `qwen3.6:35b-mlx` (21.9 GB) |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | 4 fixed Markdown sections (Obsidian weekly-note format) |

## Usage

```bash
# Concatenate the week's daily notes and write the weekly note:
cat ~/vault/Daily/2026-06-0{1,2,3,4,5}.md | ./run.sh > "Weekly/2026-W23.md"

# Or paste a brain dump of how the week went:
./run.sh "$(pbpaste)"
```

Pairs naturally with the vault rituals: run after `/eod` notes have accumulated, ahead of
the `weekly-signals` / `weekly-learnings` pass.

## Why this alias

This is the most demanding of the four, turning scattered, contradictory notes into three
*real* wins, the honest misses, the energy pattern underneath, and a single defensible focus
is synthesis and judgment, not extraction. So it runs on `quality` (qwen3.6:35b-mlx), the
strongest local model, which also routes its thinking to a separate channel (clean review,
no `strip_think` needed; `strip_reasoning`/`answer_anchor` are an inert fallback).

## Desktop (Hermes app)

The desktop/dashboard discovers **profiles**, not this repo's `run.sh` agents. Register it
once (re-run after editing `prompt.md` or the model alias):

```bash
bin/gen-profiles.sh weekly-review-synthesis   # → ~/.hermes/profiles/weekly-review-synthesis/
hermes profile list                           # confirm it appears (model=quality)
hermes desktop                                # select it as a chat persona
```

See [DESKTOP_COMPAT.md](../DESKTOP_COMPAT.md) for the discovery mechanism and the
bare-`hermes chat` caveat.

## Tuning

- The four sections and the "pick ONE focus" constraint live in `prompt.md`. If you change
  the first heading, update `answer_anchor` in `agent.yaml` to match.
- `quality` (~22 GB) is shared with `vault-distiller`, `lead-designer`, `gtm-planner`, etc.
  Fine, they run one at a time; just don't co-resident two large models.
- A full week of verbose daily notes can approach the context floor. If it's huge, run
  `meeting-to-actions` or a quick summary on each day first, then synthesize the summaries.
