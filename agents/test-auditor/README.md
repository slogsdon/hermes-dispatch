# test-auditor

Audits generated tests for **wrong expectations** before any code is written — catching the
hardcoded expected value the test author got wrong. It re-derives computed values from the
spec and converts magic numbers into runtime-evaluated expressions so the fix can't
re-introduce an arithmetic error.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | up to 3 (review + rewrite the suite) |
| **Reads** | the spec (`===== plan =====`) and the tests (`===== tests =====`) |
| **Writes** | `## Audit` … audit notes + the corrected test files |

## Usage

```bash
{ printf '===== plan =====\n'; cat plan.md;
  printf '\n===== tests =====\n'; cat tests.md; } | ./run.sh
```

## Role

The `test-audit` step of the dev-workflow pipeline, between tests and code:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
A bad test that slips through either blocks a correct implementation or forces buggy code, so
this judgment runs on the strongest local reasoner (`max`).
