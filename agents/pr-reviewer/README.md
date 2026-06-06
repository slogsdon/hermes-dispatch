# pr-reviewer

Reviews a unified diff against a fixed **five-axis rubric** (correctness, readability,
architecture, security, performance) and returns a verdict + severity-tagged findings.
A fast local pre-review before you open or merge a PR.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | 1 (one-shot judge) |
| **Output** | `## Verdict` / `## Findings` / `## Tests` |

## Usage

Pipe a diff straight in:

```bash
git diff main...HEAD |./run.sh
git show <sha> |./run.sh
gh pr diff 123 |./run.sh

# Inline snippet review:
./run.sh "$(pbpaste)"
```

Each finding is `[SEV] file:line, problem → fix`, with `SEV ∈ {BLOCKER, MAJOR, MINOR, NIT}`.

## Why this alias

Escalated from `balanced` to `max`. In testing the smaller model **inverted a security finding**: it endorsed a timing-unsafe `===` comparison
as "acceptable" and approved a diff that should have been rejected. Code review (especially
security) needs the strongest local reasoner, so this is the one review agent that earns the
`max` tier. When the backing model routes its thinking to a separate channel, output stays clean under
the project config's `show_reasoning: false` (no chain-of-thought to strip). The trade-off is
a slower cold load; worth it for a gate you actually trust. For a fast, cheap *triage* pass
where you don't need security-grade judgment, `alias: balanced` still works.

## Scope & tuning

- This reviews **only what's in the diff**. For whole-repo or cross-file architectural
 review, set `toolsets: file` + `max_turns: 5` so it can read surrounding context, at
 the cost of speed and determinism.
- It complements, not replaces, a cloud `/code-review`, use this as the always-on,
 zero-cost first pass.
