# seo-reviewer

Audits a page or content draft for **on-page SEO + AEO** (answer-engine optimization)
against a fixed rubric and returns a verdict + severity-tagged findings + quick wins. The
qualitative counterpart to `seo-tester`, and a fast local pre-check for the kind of work
the `ai-visibility-audit` / `design-audit-report` skills do at scale.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | `## Verdict` / `## Findings` / `## Quick Wins` |

## Usage

```bash
cat post.md |./run.sh

./run.sh "Target keyword: hermes minimal agents.
Title: Build a minimal local agent in five flags
Meta:...
Body:..."
```

## Why this alias

Escalated from `balanced` to `max`, same move as
`pr-reviewer`. In testing, got the two most checkable facts wrong (called a 218-char
meta "160/perfect", miscounted headings) and miscalibrated severities, which undermines a
qualitative audit. is the stronger reasoner; its thinking is on a separate channel,
so output stays clean under the project config's `show_reasoning: false`. AEO judgement (can
an AI lift a clean answer?) is built into the rubric, not bolted on. For purely *objective*
SEO facts (lengths, counts), prefer the deterministic [`seo-tester`](../seo-tester/), this
agent is for the qualitative read.

## Pairs with

- `seo-tester`, for the **machine-readable pass/fail** version (CI-style gating).
- `blog-drafter` → `seo-reviewer` → fix → publish.
