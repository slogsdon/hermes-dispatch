# gtm-executor

Turns a GTM plan (or brief) into **concrete, paste-ready launch assets**: announcement,
outreach email, landing headlines, CTA variants, one-line pitch. The execution half of the
GTM pair, `gtm-planner` decides the strategy, this writes the copy.

| | |
|---|---|
| **Alias** | `writing` |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | 5 asset sections (or a custom set) |

## Usage

```bash
# Chain from the planner:
cat brief.md |./../gtm-planner/run.sh |./run.sh

# Direct, with a custom asset list:
./run.sh "Plan: <paste>. Just give me the announcement + 3 subject lines."
```

## Why this alias

`writing` is the long-form copy slot, enough capacity for coherent,
on-message assets. `--ignore-rules` keeps the voice set by the prompt (honest, technical,
no hype), not by a vault persona. `[TK: …]` markers flag any fact the plan didn't
supply, grep for `TK` before shipping.

## Pairs with

`gtm-planner` (upstream strategy) and `social-media-marketer` (downstream channel variants
of the announcement).
