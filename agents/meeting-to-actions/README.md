# meeting-to-actions

Turns raw meeting notes or a transcript into a clean, **Obsidian-ready** summary: decisions
made, action items (with owner + due date as Obsidian task checkboxes), open questions, and
follow-ups. Reasons through what actually mattered and drops the filler.

| | |
|---|---|
| **Alias** | `reasoning` |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | 4 fixed Markdown sections (Obsidian tasks in Action Items) |

## Usage

```bash
# From a notes file:
cat ~/notes/standup.md |./run.sh

# Straight into a dated vault note:
pbpaste |./run.sh > "Meetings/$(date +%F) product sync.md"
```

Action items come out as Obsidian Tasks-plugin checkboxes so they roll up in your task
queries automatically:

```markdown
## Action Items
- [ ] Draft the migration RFC, @shane 📅 2026-06-10
- [ ] Confirm the vendor SLA numbers, @priya
```

## Why this alias

Pulling the real decisions and owned actions out of rambling notes is a **judgment** task,
not field extraction, so it runs on `reasoning`, the reasoning slot, rather
than the `structured` structured-output model the JSON agents use.

> ** in the harness:** it used to fail because Hermes sent a tools array its
> Ollama template rejects. The project home now disables **all** toolsets, so zero tools are
> sent and `reasoning` runs cleanly, verified. See the top-level README's tool-compatibility
> note. Its reasoning goes to a separate channel that `display.show_reasoning: false`
> suppresses, so stdout is clean Markdown; `strip_reasoning`/`answer_anchor` are an inert
> fallback.

## Desktop (Hermes app)

The desktop/dashboard discovers **profiles**, not this repo's `run.sh` agents. Register it
once (re-run after editing `prompt.md` or the model alias):

```bash
bin/gen-profiles.sh meeting-to-actions # → ~/.hermes/profiles/meeting-to-actions/
hermes profile list # confirm it appears (model=analyze)
hermes desktop # select it as a chat persona
```

See [DESKTOP_COMPAT.md](../DESKTOP_COMPAT.md) for the discovery mechanism and why a bare
`hermes chat -m analyze` is *not* a valid test (it runs against the default home, which
sends tools and renders a reasoning block, the project home that `run.sh`/the profile use
disables both).

## Tuning

- The four sections live in `prompt.md`. Add/rename sections there, if you change the first
 heading, update `answer_anchor` in `agent.yaml` to match it.
- Keep transcripts under the real `reasoning` num_ctx (~40K). For a long all-hands, summarize
 in chunks and re-run on the concatenated summaries.
- Want a faster, lighter pass that skips the reasoning? Switch to `alias: writing`,
 also tool-compatible, less judgment.
