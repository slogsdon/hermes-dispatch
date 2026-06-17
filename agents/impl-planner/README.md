# impl-planner

Turns a chosen direction into an **ordered, testable implementation plan** — the keystone
artifact a developer or coding agent executes verbatim, each step with a concrete "done when".

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | up to 6 (interactive scope clarify, or one-shot) |
| **Reads** | the chosen direction (and any brief / stack context) |
| **Writes** | `## Overview` … multi-section Markdown plan |

## Usage

```bash
./direction-explorer/run.sh < brief | ./run.sh
echo "direction…" | ./run.sh
```

## Role

Step 3 of the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
A wrong decomposition or a missing acceptance check wastes the whole build, so planning runs
on the strongest local reasoner (`max`). The plan is what the gate reviews before any code is
written.
