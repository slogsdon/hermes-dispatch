# release-prep

Turns a change summary into a **pre-launch checklist** — blast radius, a rollback plan, and a
go/no-go call, loudly flagging anything destructive (e.g. an irreversible migration). The
last gate before production.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | 1 (one-shot gate) |
| **Reads** | the change summary / diff summary / release notes for what's shipping |
| **Writes** | `## Pre-Flight Checklist` … checklist + rollback + go/no-go |

## Usage

```bash
./run.sh "$(git log --oneline main..HEAD)"
echo "what's shipping…" | ./run.sh
```

## Role

A release-stage agent in the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
Judging launch risk and rollback reversibility is expensive to get wrong, so it runs on the
strongest local reasoner (`max`). Pairs with pr-describer at the finish line.
