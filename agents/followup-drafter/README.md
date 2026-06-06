# followup-drafter

Turns the context of a last interaction (what was discussed, where it ended, the next step)
into a **short, natural follow-up email**, max 150 words, professional, and deliberately not
template-shaped. The back of the sales pipeline: keeps a deal moving after the call or the
proposal.

| | |
|---|---|
| **Alias** | `writing` |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | subject + ≤150-word body |

## Usage

```bash
./run.sh "Discussed their API docs pain on today's call. Ended agreeing I'd send a scope. \
Next step: I send the proposal by Friday."

cat call-notes.md |./run.sh

# Close the loop after a proposal:
cat scope-brief.md |./../proposal-writer/run.sh # (send the proposal, then:)
./run.sh "Sent the docs-revamp proposal Tuesday. No reply yet. Want to nudge gently."
```

## Why this alias

The email is short, but the bar is *natural*, it must not read like a mail-merge. `writing` is the long-form writer and reads least like a template among the local models.
`--ignore-rules` keeps the voice set by the prompt (human, direct, no "I hope this finds you
well"), and a hard 150-word cap keeps it inbox-friendly. `[TK: …]` markers flag any detail
the context didn't supply.

## Desktop / web UI

The `run.sh` CLI path works out of the box. To use this agent as a chat persona in the
Hermes **desktop** app (or `hermes dashboard` web UI), register it as a profile first, the
desktop discovers profiles, not this repo's shell wrappers (see [ARCHITECTURE.md](../ARCHITECTURE.md#2-exposing-agents-in-the-hermes-desktop-app)):

```bash
bin/gen-profiles.sh followup-drafter # materialize the profile (model + persona pinned)
hermes profile list # → followup-drafter appears with model=write
hermes desktop # pick it as a chat persona
```

## Pairs with

`prospect-researcher`, `discovery-prep`, and `proposal-writer` (upstream stages this email
follows up on).
