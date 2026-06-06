# prospect-researcher

Turns a company name and/or contact into a **sales-call research brief**: company summary,
likely pain points mapped to Shane's lanes (developer advocacy, payments/fintech, AI
tooling), talking points, and 3 sharp discovery questions. The front of the sales pipeline, 
`discovery-prep` takes it into the call, `followup-drafter` closes the loop after.

| | |
|---|---|
| **Alias** | `quality` → `qwen3.6:35b-mlx` (21.9 GB) |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | 4 fixed Markdown sections |

## Usage

```bash
./run.sh "Stripe, meeting with a Developer Relations lead about their API docs program."

cat prospect-notes.md | ./run.sh

# Hand straight into pre-call prep:
./run.sh "Acme Payments, VP Eng" | ./../discovery-prep/run.sh
```

## Why this alias

Sales research is accuracy-sensitive, a fabricated fact or a wrong pain point is worse than
no brief, so it earns `quality` (qwen3.6:35b-mlx), the strongest local model, which also
routes its thinking to a separate channel (clean brief, no `strip_think` needed). The prompt
forces `(inferred)` markers and bans invented numbers so the brief stays honest.

## Desktop / web UI

The `run.sh` CLI path works out of the box. To use this agent as a chat persona in the
Hermes **desktop** app (or `hermes dashboard` web UI), register it as a profile first, the
desktop discovers profiles, not this repo's shell wrappers (see [ARCHITECTURE.md](../ARCHITECTURE.md#2-exposing-agents-in-the-hermes-desktop-app)):

```bash
bin/gen-profiles.sh prospect-researcher   # materialize the profile (model + persona pinned)
hermes profile list                        # → prospect-researcher appears with model=quality
hermes desktop                             # pick it as a chat persona
```

## Pairs with

`discovery-prep` (downstream pre-call prep) and `followup-drafter` (downstream post-call
email).
