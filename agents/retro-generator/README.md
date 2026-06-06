# retro-generator

Turns raw end-of-project notes into a structured **retrospective**: wins, misses, root
causes, and exactly 3 concrete changes for next time. Output is Obsidian-ready Markdown
(headings + `#tags`) that drops straight into the vault as a retro note.

| | |
|---|---|
| **Alias** | `reasoning` |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | `## Wins` / `## Misses` / `## Root Causes` / `## Changes for Next Time` / `## Tags` |

## Usage

Feed it the raw notes, timeline events, what worked, what didn't:

```bash
cat project-notes.md |./run.sh > retro.md

./run.sh "Project: 6-week client rebuild. Shipped 2 weeks late. Logo assets arrived in
week 5. Client added a blog mid-project. Dev velocity was good once scope settled. QA
caught 3 launch-blockers because we left it to the last day."

# Hand the result to the obsidian skill to file it (this agent never touches the vault):
cat project-notes.md |./run.sh # then: obsidian create file='Retros/<project> Retro'...
```

## Why this alias

A retro is genuine synthesis: reading messy notes, separating symptom from root cause,
and deriving a few durable changes. That is reasoning over the material, not extraction,
so it runs on the `reasoning` role. When the backing model routes its thinking to a
separate channel, output stays clean under the project config's `show_reasoning: false`.

## Tuning

- The "Changes for Next Time" section is capped at **exactly 3** on purpose, a retro that
 produces 12 action items produces zero. Each must trace to a root cause.
- Inferred causes are marked `(inferred)`, the model flags what it's reading between the
 lines of thin notes; review those before treating them as findings.
- Pairs naturally after a delivery: `scope-creep-detector` (during) →
 `status-update-writer` (throughout) → `retro-generator` (at close).

## Run it in the desktop

The Hermes desktop/dashboard discovers **profiles**, not `run.sh` wrappers. Register this
agent as a profile once, then it's a selectable chat persona with the same model + config:

```bash
bin/gen-profiles.sh retro-generator # or just `bin/gen-profiles.sh` for all
hermes profile list # confirm it appears (model=quality)
hermes desktop # pick the persona
```

See [DESKTOP_COMPAT.md](../DESKTOP_COMPAT.md) for the discovery mechanism and CLI-vs-desktop
differences.
