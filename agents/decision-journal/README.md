# decision-journal

Captures a decision Shane is facing as a durable Obsidian note written **for future-Shane**:
the decision, its context and stakes, the options, the *reasoning at the time* (the
assumptions and the bet), the expected outcome, and a "check back" date. Built so a call can
be audited honestly months later, not to make the call for him.

| | |
|---|---|
| **Alias** | `analyze` → `deepseek-r1:14b` (9.0 GB) |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | 6 fixed Markdown sections → save under `Decisions/` |

## Usage

```bash
# Pass today's date so the "check back" date is absolute, and write into Decisions/:
./run.sh "Today is $(date +%F). Decision: hire a contractor for the API rewrite or do it \
in-house. Options: (a) contractor, faster, ~\$15k; (b) in-house, slower, builds knowledge. \
Stakes: launch slips if we're late; in-house ties up me for 6 weeks." \
  > "Decisions/$(date +%F) api-rewrite-staffing.md"

# Or from a brief file:
cat decision-brief.md | ./run.sh
```

The note ends with an Obsidian calendar callout so the review surfaces later:

```markdown
## Check Back
> [!calendar] Review on 2026-09-04, did the contractor path actually beat in-house on time?
```

## Why this alias

The whole point is to **elicit and structure the reasoning**, why this, why now, what's the
load-bearing assumption, what would change the answer, so it runs on `analyze`
(deepseek-r1:14b), the reasoning slot, not the `pipeline` extraction model.

> **deepseek-r1 in the harness:** previously failed because Hermes sent a tools array its
> Ollama template rejects; the project home now disables **all** toolsets, so zero tools are
> sent and `analyze` runs cleanly (verified, see the top-level README tool-compatibility
> note). Reasoning goes to a suppressed channel (`display.show_reasoning: false`), so stdout
> is clean Markdown; `strip_reasoning`/`answer_anchor` are an inert fallback.

## Desktop (Hermes app)

The desktop/dashboard discovers **profiles**, not this repo's `run.sh` agents. Register it
once (re-run after editing `prompt.md` or the model alias):

```bash
bin/gen-profiles.sh decision-journal   # → ~/.hermes/profiles/decision-journal/
hermes profile list                    # confirm it appears (model=analyze)
hermes desktop                         # select it as a chat persona
```

The desktop runs an interactive chat, handy for *talking through* a decision before
capturing it. For the deterministic note you save into `Decisions/`, use `run.sh`. See
[DESKTOP_COMPAT.md](../DESKTOP_COMPAT.md) for the discovery mechanism and the
bare-`hermes chat` caveat.

## Tuning

- Always pass the current date in the INPUT if you want an absolute review date, the model
  is instructed never to fabricate "today" and will otherwise give an interval ("~90 days").
- The six sections live in `prompt.md`. If you change the first heading, update
  `answer_anchor` in `agent.yaml` to match.
- The note is deliberately **not** auto-filed, pipe it into `Decisions/` yourself (or hand
  it to the `obsidian` skill) so you stay in the loop on what gets committed to the vault.
