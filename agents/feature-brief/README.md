# feature-brief

Turns a raw one-line idea into a **business-context brief** — persona, opportunity,
monetization, KPIs, and risks. The first artifact in the dev-workflow pipeline; everything
downstream is framed by the bet it names.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | up to 4 (one-shot, or a short clarify first) |
| **Reads** | a raw idea / feature request (piped or as an argument) |
| **Writes** | `## Persona` … multi-section Markdown brief |

## Usage

```bash
./run.sh "an app that drafts standup updates from git history"
echo "idea…" | ./run.sh
```

If a load-bearing detail is missing it asks up to two clarifying questions before producing
the brief; on a one-shot run it fills gaps with `(assumed)` and delivers anyway.

## Role

Step 1 of the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
Framing the commercial bet is judgment-critical — a wrong frame poisons every later stage —
so it runs on the strongest local reasoner (`max`).
