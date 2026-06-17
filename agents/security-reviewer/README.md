# security-reviewer

Reviews a diff for **OWASP-oriented security findings** — injection, authz gaps,
timing-unsafe comparisons, secret handling, unsafe deserialization, and the like. A
dedicated security gate that goes deeper than a general review's single security axis.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | 1 (one-shot judge) |
| **Reads** | the diff or code to review |
| **Writes** | `## Verdict` … verdict + findings |

## Usage

```bash
git diff main... | ./run.sh
gh pr diff 123   | ./run.sh
```

## Role

The hardening gate of the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
Security review is where a weak model is actively dangerous — a smaller model has been seen
endorse a timing-unsafe comparison and approve a diff that should be blocked — so this runs
on the strongest local reasoner (`max`). It complements pr-reviewer, not replaces it.
