# cashflow-summarizer

Reads a list of transactions (paste, CSV, or piped file) and returns a **weekly cash
digest**: total in, total out, net, the top 3 expense categories, and a one-line cash-health
verdict. The reasoning-slot agent, it does arithmetic and judgment over numbers, not field
extraction.

| | |
|---|---|
| **Alias** | `analyze` → `deepseek-r1:14b` |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | `## Cash Digest` / `## Top Expenses` / `## Verdict` |

## Usage

```bash
cat transactions.csv | ./run.sh
pbpaste | ./run.sh

./run.sh "Stripe payout +4200; AWS -380; Figma -45; Contractor -1500; Rent -2200; Ads -300"
```

```
## Cash Digest
- **Total in:** $4,200 USD
- **Total out:** $4,425 USD
- **Net:** -$225 USD

## Top Expenses
1. Rent, $2,200 (1 txn)
2. Contractor, $1,500 (1 txn)
3. Marketing, $300 (1 txn)

## Verdict
Watch, net-negative week; outflows edged past a single lumpy payout.
```

## Why this alias

`analyze` (deepseek-r1:14b) is the only roster model billed for "reasoning/debugging," and
this is the rare ops task that earns it: summing signed amounts, bucketing and ranking
expense categories, and forming a health call are reasoning over numbers, a `pipeline`
(no-thinking) model would extract fields fine but is the wrong tool for judgment. `analyze`
runs cleanly under this project's home (all toolsets disabled, so deepseek-r1's
tool-rejecting template never sees a tools array; `show_reasoning: false` suppresses the
rendered chain-of-thought). `strip_think` + `strip_reasoning` are inert belt-and-braces.

## Scope & tuning

- Keep inputs under deepseek-r1's real context (~40K tokens), a week of transactions is
  well within that. For a month, pre-aggregate or chunk by week.
- The categories and the `Healthy/Watch/Tight` verdict scale live in `prompt.md`. Adjust to
  match your chart of accounts.
- Want it faster and don't need the reasoning? `alias: write` (gpt-oss:20b) or `quality`
  also handle the prose, but you lose the careful arithmetic deepseek does best.

## In the Hermes desktop app

The desktop app (`hermes desktop`) and web dashboard (`hermes dashboard`) discover agents as
**profiles**, not shell wrappers. Registration is automatic, `bin/gen-profiles.sh`
auto-discovers every agent dir (any folder with `agent.yaml` + `prompt.md`), so just run it
after adding or editing an agent:

```bash
bin/gen-profiles.sh                 # materialize one profile per agent into ~/.hermes/profiles/
hermes profile list                 # confirm `cashflow-summarizer` appears with model `analyze`
hermes desktop                      # → pick `cashflow-summarizer` as a chat persona (or: hermes dashboard)
```

The zero-build web UI (`python3 webui/serve.py`) also lists this agent automatically. See
[ARCHITECTURE.md](ARCHITECTURE.md) §2 for the full exposure model.
