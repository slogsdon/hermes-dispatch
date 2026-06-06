# status-update-writer

Turns rough **done / blocked / next** bullets into a clean, confident client status update
you can send as-is. No hedging, no fluff, capped at 200 words, with a single explicit
"next action required from you" line when the client actually owes you something.

| | |
|---|---|
| **Alias** | `writing` |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | `## Status Update` + Completed / In progress·blocked / Next (+ action line) |

## Usage

```bash
./run.sh "DONE: auth + onboarding flow shipped to staging, client copy integrated.
BLOCKED: final logo assets not received, homepage hero is stubbed.
NEXT: wire up the dashboard, then QA pass before launch."

# From a notes file:
cat standup-notes.md |./run.sh
```

Produces a paste-ready update with no greeting or sign-off, so it drops straight into an
email or Slack message.

## Why this alias

A status update is a short composition task, tone, flow, and restraint matter more than
reasoning, so it uses `writing`, the roster's long-form writing slot, which is
also tool-compatible. The prompt does the heavy lifting: it bans the hedging and filler
that make updates read as nervous, and enforces the 200-word cap.

## Tuning

- The "next action required from you" line is **conditional**, it only appears when the
 input implies the client owes something. Feed it a blocker that's on the client to get it.
- It won't invent dates; if you want firm timing in the output, put the dates in the input.
- For a warmer or more formal register, add a one-line tone note to the input
 (e.g. "tone: warm but brief"), the prompt's defaults are confident-and-neutral.

## Run it in the desktop

The Hermes desktop/dashboard discovers **profiles**, not `run.sh` wrappers. Register this
agent as a profile once, then it's a selectable chat persona with the same model + config:

```bash
bin/gen-profiles.sh status-update-writer # or just `bin/gen-profiles.sh` for all
hermes profile list # confirm it appears (model=write)
hermes desktop # pick the persona
```

See [DESKTOP_COMPAT.md](../DESKTOP_COMPAT.md) for the discovery mechanism and CLI-vs-desktop
differences.
