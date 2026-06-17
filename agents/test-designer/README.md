# test-designer

Writes the **failing tests first** — runnable test code (correct imports, idiomatic
framework, real assertions) for a task before any implementation exists. The TDD red step.

| | |
|---|---|
| **Alias** | `code` |
| **Tools** | none |
| **Turns** | up to 3 (one-shot, or a short language/framework clarify) |
| **Reads** | the task / behavior to test (ideally with acceptance criteria) |
| **Writes** | `## Test Plan` + a fenced code block + the run command |

## Usage

```bash
./run.sh "parse an ISO-8601 duration string into seconds; reject malformed input"
echo "task + acceptance criteria…" | ./run.sh
```

## Role

Step 4 (red) of the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
Producing real test code routes to the `code` tier; the tests it writes are checked by
test-auditor before code-generator implements against them.
