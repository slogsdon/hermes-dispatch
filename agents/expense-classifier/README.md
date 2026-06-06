# expense-classifier

Takes raw transaction descriptions and classifies each into a tax-relevant category, then
returns the rows as **CSV with a `category` column appended**, ready to import into a
ledger or pivot for a Schedule C. Batch-first: feed it the whole export at once.

| | |
|---|---|
| **Alias** | `structured` |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | input CSV + appended `category` column |
| **Categories** | `software`, `travel`, `meals`, `contractor`, `equipment`, `marketing`, `professional services`, `other` |

## Usage

```bash
cat transactions.csv |./run.sh > classified.csv

./run.sh "$(pbpaste)"
```

```
date,description,amount,category
2026-06-01,AWS us-east-1,380.00,software
2026-06-02,United SFO->JFK,612.40,travel
2026-06-02,Blue Bottle Coffee,18.00,meals
2026-06-03,Upwork - React dev,1500.00,contractor
2026-06-04,Meta Ads,300.00,marketing
```

## Why this alias (not `fast`)

Batch classification into a fixed enum is the `structured` sweet spot, "fast
structured tasks, *no thinking*". The named-for-the-job `fast` is
a thinking model that streams chain-of-thought, which would interleave with the rows and
break the CSV. Note `parse_last_line` is **off** here (unlike `triage-router`/`invoice-tracker`):
the output is multi-row, so collapsing to the last line would throw away every row but one.

## Scope & tuning

- The category set lives in `prompt.md`, edit it to match your chart of accounts; keep the
 "exactly one category per row, CSV only" contract intact.
- Keep batches within `structured`'s real context (~32K tokens). For huge exports, split into
 chunks (e.g. `split -l 200`) and concatenate the results, re-using the header from the
 first chunk only.
- Classification is a starting point, not tax advice, review `other` and `meals` (often
 partially deductible) before filing.

## In the Hermes desktop app

The desktop app (`hermes desktop`) and web dashboard (`hermes dashboard`) discover agents as
**profiles**, not shell wrappers. Registration is automatic, `bin/gen-profiles.sh`
auto-discovers every agent dir (any folder with `agent.yaml` + `prompt.md`), so just run it
after adding or editing an agent:

```bash
bin/gen-profiles.sh # materialize one profile per agent into ~/.hermes/profiles/
hermes profile list # confirm `expense-classifier` appears with model `structured`
hermes desktop # → pick `expense-classifier` as a chat persona (or: hermes dashboard)
```

The zero-build web UI (`python3 webui/serve.py`) also lists this agent automatically. See
[ARCHITECTURE.md](ARCHITECTURE.md) §2 for the full exposure model.
