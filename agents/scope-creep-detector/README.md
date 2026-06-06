# scope-creep-detector

Given the **original agreed scope** and a **new client request**, classifies the request
as in scope, out of scope, or ambiguous, and drafts the exact language to respond with.
A client-delivery guardrail: it catches "while you're at it" additions before they quietly
become unpaid work, and hands you a professional boundary to send.

| | |
|---|---|
| **Alias** | `reasoning` |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | `## Verdict` / `## Reasoning` / `## Suggested Response` |

## Usage

Paste both halves in, each clearly labeled:

```bash
./run.sh "AGREED SCOPE: 5-page marketing site, copy provided by client, one round of
revisions. NEW REQUEST: can you also wire up a blog with categories and an email signup?"

# From a file holding the scope + the new request:
cat scope-and-request.md |./run.sh
```

Example out-of-scope response it produces:

> That's outside the current engagement, I can scope that separately as a small add-on
> (blog index + post template + Mailchimp signup), roughly a half-day of work.

## Why this alias

Deciding in/out/ambiguous against a contract is genuine reasoning, drawing a boundary,
weighing explicit terms against implicit ones, so it goes to `reasoning`,
the roster's dedicated **reasoning slot**, rather than spending the heavier `max` tier
on it.

> **Wait, isn't `reasoning` the model `gtm-planner` deliberately avoids?** It was: Hermes
> always sent a non-empty tools array, and's Ollama template hard-rejects it
> (`does not support tools`). The project home now disables **all** toolsets, so zero tools
> reach the model and `reasoning` runs cleanly (verified, see the top-level README's
> tool-compatibility note). This is the agent that actually puts that fix to use.

## Tuning

- It defaults to `AMBIGUOUS` rather than forcing a call it can't defend, tighten the
 prompt's "when in doubt" rule if you want it to lean more aggressively to OUT OF SCOPE.
- Keep inputs under's real `num_ctx` (~40K); paste the relevant scope clauses, not
 the entire master agreement.
- The suggested response is meant to be copy-paste-ready; review the named add-on before
 sending, it's the model's best guess at how to frame the separate work.

## Run it in the desktop

The Hermes desktop/dashboard discovers **profiles**, not `run.sh` wrappers. Register this
agent as a profile once, then it's a selectable chat persona (with the same model + minimal
config, so `reasoning` runs clean, no reasoning-block leak, no tool error):

```bash
bin/gen-profiles.sh scope-creep-detector # or just `bin/gen-profiles.sh` for all
hermes profile list # confirm it appears (model=analyze)
hermes desktop # pick the persona
```

See [DESKTOP_COMPAT.md](../DESKTOP_COMPAT.md) for the full discovery mechanism and the
CLI-vs-desktop differences. Note: raw `hermes chat -m analyze` against `~/.hermes` works but
leaks the `┌─ Reasoning` block (that home has `show_reasoning: true`); `run.sh` and the
generated profile both suppress it.
