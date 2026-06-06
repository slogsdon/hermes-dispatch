# proposal-writer

Turns a scope brief (problem, deliverables, timeline, rough budget) into a **structured,
client-ready proposal**: executive summary, scope of work, deliverables, timeline,
investment, and terms. The mid-pipeline closer, runs after discovery has surfaced the need.

| | |
|---|---|
| **Alias** | `write` → `gpt-oss:20b` (13.8 GB) |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | 6 fixed Markdown sections |

## Usage

```bash
cat scope-brief.md | ./run.sh

./run.sh "Problem: client's API docs drive support tickets. Deliverables: docs audit + \
quickstart + 3 samples. Timeline: 6 weeks. Budget: ~\$18k."
```

## Why this alias

A proposal is polished, multi-section prose where tone and specificity carry the sale, so it
runs on `write` (gpt-oss:20b), the long-form copy slot. `--ignore-rules` keeps the voice set
by the prompt (confident, specific, no boilerplate), not Shane's vault persona. `[TK: …]`
markers flag any fact the brief didn't supply, grep for `TK` before sending.

## Desktop / web UI

The `run.sh` CLI path works out of the box. To use this agent as a chat persona in the
Hermes **desktop** app (or `hermes dashboard` web UI), register it as a profile first, the
desktop discovers profiles, not this repo's shell wrappers (see [ARCHITECTURE.md](../ARCHITECTURE.md#2-exposing-agents-in-the-hermes-desktop-app)):

```bash
bin/gen-profiles.sh proposal-writer   # materialize the profile (model + persona pinned)
hermes profile list                   # → proposal-writer appears with model=write
hermes desktop                        # pick it as a chat persona
```

## Pairs with

`discovery-prep` / `prospect-researcher` (upstream, surface the need this proposal answers)
and `followup-drafter` (downstream, the email that lands it).
