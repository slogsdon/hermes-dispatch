# privacy-checker

Reviews a **privacy policy or DPA** and returns a **data map** (what's collected, who it's
shared with, retention, user rights) plus a **gap list** against GDPR / CCPA basics. The
data-handling companion to `tos-reviewer`: run it on a vendor before you trust them with
your, or your clients', data.

> **Not legal advice.** This agent flags issues for awareness only. For anything
> consequential, a signed DPA, a compliance commitment, handling of client or end-user
> data, consult a lawyer or privacy professional.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | 1 (one-shot judge) |
| **Output** | `## Data Map` / `## Gaps` |

## What it checks

Data collected · sharing & third parties (incl. sale/ad-sharing, cross-border transfers) ·
retention periods · user rights (access, deletion, export, opt-out) · missing required
disclosures (GDPR legal basis / transfer mechanism / rights; CCPA notice / Do-Not-Sell path).

## Usage

Pipe the policy straight in:

```bash
pbpaste |./run.sh
cat privacy-policy.txt |./run.sh
curl -s https://x.com/privacy.txt |./run.sh

# Inline:
./run.sh "Company: Acme. This is their DPA. Text:..."
```

The **Data Map** summarizes the flows; **Gaps** is `[SEV] area, missing → expected`, with
`SEV ∈ {BLOCKER, WARN, NOTE}`. Absences are findings: "no retention period stated" is a gap,
not an assumption.

## Why this alias

Uses `max`, same escalation as `tos-reviewer` / `pr-reviewer`. Spotting
a missing GDPR/CCPA disclosure or an undisclosed third-party data flow is reasoning over
dense policy text where a small model's miss is a real compliance gap. routes its
thinking to a separate channel, so output stays clean under the project config's
`show_reasoning: false`. GDPR/CCPA checks here are basics-level awareness, not a certified audit.

## Desktop / web UI

The `run.sh` CLI path works out of the box. To use this agent as a chat persona in the
Hermes **desktop** app (or `hermes dashboard` web UI), register it as a profile first, the
desktop discovers profiles, not this repo's shell wrappers (see [ARCHITECTURE.md](../ARCHITECTURE.md#2-exposing-agents-in-the-hermes-desktop-app)):

```bash
bin/gen-profiles.sh privacy-checker # materialize the profile (model + persona pinned)
hermes profile list # → privacy-checker appears with model=quality
hermes desktop # pick it as a chat persona
```

## Pairs with

- `tos-reviewer`, for the **contract / risk** read of the same vendor's terms.
