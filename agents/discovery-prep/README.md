# discovery-prep

Turns a prospect name/company plus a meeting goal into a **pre-call discovery plan**:
factual company background, 5 open-ended questions ordered by conversation flow, and a
one-paragraph "what I want to learn" framing to set intention before the call. Sits between
`prospect-researcher` (the upstream brief) and the call itself.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | 3 fixed Markdown sections |

## Usage

```bash
./run.sh "Prospect: Acme Payments (Series B fintech). Goal: scope a developer-docs revamp."

cat prospect-brief.md |./run.sh

# Chain from the researcher:
./run.sh "Stripe, DevRel lead" |./../discovery-prep/run.sh
```

## Why this alias

Sequencing questions for conversational flow and framing call intent is a judgment step, and
the background must stay factual, so it earns `max`, the strongest
local model, which routes its thinking to a separate channel (clean plan, no `strip_think`
needed). The prompt forces `(inferred)` markers and bans invented facts.

## Desktop / web UI

The `run.sh` CLI path works out of the box. To use this agent as a chat persona in the
Hermes **desktop** app (or `hermes dashboard` web UI), register it as a profile first, the
desktop discovers profiles, not this repo's shell wrappers (see [ARCHITECTURE.md](../ARCHITECTURE.md#2-exposing-agents-in-the-hermes-desktop-app)):

```bash
bin/gen-profiles.sh discovery-prep # materialize the profile (model + persona pinned)
hermes profile list # → discovery-prep appears with model=quality
hermes desktop # pick it as a chat persona
```

## Pairs with

`prospect-researcher` (upstream research brief) and `followup-drafter` (downstream post-call
email).
