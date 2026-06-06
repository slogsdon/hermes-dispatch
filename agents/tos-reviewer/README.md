# tos-reviewer

A fast **risk pass** on terms of service, vendor agreements, or platform terms *before*
you accept or sign. Returns an overall verdict plus severity-tagged flags, each with the
quoted clause, a plain-English translation, and a suggested action. The legal/compliance
counterpart to `pr-reviewer`: a gate you run before committing to something hard to unwind.

> **Not legal advice.** This agent flags issues for awareness only. For anything
> consequential, real money, IP, client obligations, a signature that's hard to undo, 
> consult a lawyer. The agent says so itself when the stakes warrant it.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | 1 (one-shot judge) |
| **Output** | `## Verdict` / `## Flags` |

## What it checks

Data ownership & portability · unilateral term/price changes · auto-renewal &
cancellation · arbitration / jury-trial & class-action waivers · liability caps &
indemnification · anything touching a IP or client work.

## Usage

Pipe the terms straight in:

```bash
pbpaste |./run.sh
cat vendor-terms.txt |./run.sh
curl -s https://x.com/terms.txt |./run.sh

# Inline:
./run.sh "Vendor: Acme SaaS. Signing up for the Team plan. Terms:..."
```

Each flag is `[SEV] area, label` with `SEV ∈ {BLOCKER, WARN, NOTE}`, the quoted clause,
**Plain English**, and an **Action** (`negotiate out` / `accept` / `understand before signing`).

## Why this alias

Uses `max`, same escalation as `pr-reviewer`. A contract risk pass is
high-stakes, a missed indemnification clause or IP-assignment grant is real exposure, and
the small `balanced` model miscalibrates severity on dense legal text.
routes its thinking to a separate channel, so output stays clean under the project config's
`show_reasoning: false`. The trade-off is a slower cold load; worth it for a gate you trust.

## Desktop / web UI

The `run.sh` CLI path works out of the box. To use this agent as a chat persona in the
Hermes **desktop** app (or `hermes dashboard` web UI), register it as a profile first, the
desktop discovers profiles, not this repo's shell wrappers (see [ARCHITECTURE.md](../ARCHITECTURE.md#2-exposing-agents-in-the-hermes-desktop-app)):

```bash
bin/gen-profiles.sh tos-reviewer # materialize the profile (model + persona pinned)
hermes profile list # → tos-reviewer appears with model=quality
hermes desktop # pick it as a chat persona
```

## Pairs with

- `privacy-checker`, for the **data-handling / GDPR-CCPA** read of the same vendor.
