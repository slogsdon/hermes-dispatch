# triage-router

Classifies and routes a single item (inbox note, task, message, ticket) into a fixed enum
and emits **one line of minified JSON**, the structured-output workhorse for automation
(inbox processing, task routing, batch triage). Pipe it straight to `jq`.

| | |
|---|---|
| **Alias** | `structured` |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | `{"category","priority","route","reason"}` minified JSON |

## Usage

```bash
./run.sh "Follow up with the payments team re: webhook retries by Friday" | jq.
# {"category":"task","priority":"soon","route":"project","reason":"actionable follow-up with deadline"}

# Batch a directory of inbox files:
for f in ~/inbox/*.md; do
 echo "$f -> $(cat "$f" |./run.sh)"
done
```

## Why this alias (not `fast`)

The obvious pick is `fast`, it's literally named for routing.
But the brief's live test exposed two problems with it: it's a **thinking** model that
streams chain-of-thought before the JSON even with `-Q`, and its 1.2B reasoning mis-picked
a field. So this agent uses **`structured`**, explicitly "fast structured tasks,
*no thinking*", for clean JSON. As belt-and-braces, `parse_last_line: true` keeps only the
final non-empty stdout line, so even a stray reasoning preamble can't corrupt the pipe.

## Tuning

- Want sub-second routing and can tolerate parsing the last line? Switch to
 `alias: fast`, `parse_last_line` is already on to handle its CoT output.
- The enums live in `prompt.md`. Edit them there to fit a different routing target; keep
 the "ONLY one line of JSON" contract intact.
