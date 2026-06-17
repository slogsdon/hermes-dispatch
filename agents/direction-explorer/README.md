# direction-explorer

Takes a business-context brief and **frames the problem, generates distinct directions,
ranks them, and commits to a pick**. A diverge-then-converge brainstorm that turns a brief
into a chosen bet.

| | |
|---|---|
| **Alias** | `reasoning` |
| **Tools** | none |
| **Turns** | up to 6 (interactive diverge/converge, or one-shot) |
| **Reads** | the brief (or a raw idea + any framing) |
| **Writes** | `## Problem Frame` … framed problem + ranked directions + a pick |

## Usage

```bash
./feature-brief/run.sh "idea" | ./run.sh
echo "brief…" | ./run.sh
```

## Role

Step 2 of the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
Generating real alternatives and then judging them is exactly what the `reasoning` tier is
for; it hands a single chosen direction to the planner.
