# pr-describer

Turns a diff (and optionally the commit log) into a **PR description** — a why-focused
summary, grouped changes, an honest test plan, and a risk note. Reviewer-facing prose, ready
to paste.

| | |
|---|---|
| **Alias** | `writing` |
| **Tools** | none |
| **Turns** | 1 (diff in, PR body out) |
| **Reads** | the diff or implementation code (optionally preceded by the commit log) |
| **Writes** | `## Title` … title + summary + changes + test plan + risk |

## Usage

```bash
git diff main... | ./run.sh
{ git log --oneline main..HEAD; echo; git diff main...; } | ./run.sh
```

## Role

A release-stage agent in the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
Turning a diff into clear reviewer-facing prose is a writing task, not accuracy-critical
judgment, so it routes to the `writing` tier rather than the heavy reasoner. Pairs with
release-prep at the finish line.
