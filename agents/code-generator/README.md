# code-generator

Turns an implementation plan into **actual runnable code** — complete, runnable files, not a
prompt for a human to write code. In REFINE mode it revises existing code against review
findings.

| | |
|---|---|
| **Alias** | `code` |
| **Tools** | none |
| **Turns** | up to 2 (one-shot, with headroom for a long multi-file emit) |
| **Reads** | the plan/spec (GENERATE), or existing code + review findings (REFINE) |
| **Writes** | `## Summary` + fenced code blocks + notes |

## Usage

```bash
# GENERATE
./impl-planner/run.sh < direction | ./run.sh
./run.sh "$(cat plan.md)"

# REFINE — pipe the existing code AND the review findings back in
{ cat code.md; echo; cat findings.md; } | ./run.sh
```

## Role

The build step of the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
It implements against the audited tests on the `code` tier; its output is validated, then
reviewed before release.
