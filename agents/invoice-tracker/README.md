# invoice-tracker

Extracts vendor, amount, currency, due date, and payment status from an invoice email or
document and emits **one line of minified JSON**, the structured-output workhorse for
accounts-payable automation (logging invoices, flagging what's due, batch ingest). Pipe it
straight to `jq`.

| | |
|---|---|
| **Alias** | `pipeline` → `lfm2:24b` (14.4 GB) |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | `{"vendor","amount","currency","due_date","status","notes"}` minified JSON |

## Usage

```bash
cat invoice.txt | ./run.sh | jq .
# {"vendor":"Acme Cloud","amount":420,"currency":"USD","due_date":"2026-07-01","status":"unpaid","notes":"INV-2031, Net 30"}

./run.sh "$(pbpaste)"

# Batch a folder of saved invoice emails into one NDJSON file:
for f in ~/invoices/*.txt; do cat "$f" | ./run.sh; done > invoices.ndjson
```

## Why this alias (not `classify`)

This is field extraction against a fixed schema, exactly what `pipeline` (lfm2:24b),
"fast structured tasks, *no thinking*", is for. The named-for-the-job `classify`
(lfm2.5-thinking:1.2b) is a thinking model that streams chain-of-thought before the JSON
even with `-Q`, which corrupts the pipe and risks a mis-picked field, the same problem
documented for `triage-router`. As belt-and-braces, `parse_last_line: true` keeps only the
final non-empty stdout line, so a stray preamble can't break `jq`.

## Tuning

- The schema and `status` enum live in `prompt.md`. Edit them there to fit your ledger;
  keep the "ONLY one line of JSON" contract intact.
- The model extracts only what the invoice shows, empty/`0`/`"unknown"` over a guess.
  For OCR'd PDFs, run the text through your OCR step first; this agent takes text in.

## In the Hermes desktop app

The desktop app (`hermes desktop`) and web dashboard (`hermes dashboard`) discover agents as
**profiles**, not shell wrappers. Registration is automatic, `bin/gen-profiles.sh`
auto-discovers every agent dir (any folder with `agent.yaml` + `prompt.md`), so just run it
after adding or editing an agent:

```bash
bin/gen-profiles.sh                 # materialize one profile per agent into ~/.hermes/profiles/
hermes profile list                 # confirm `invoice-tracker` appears with model `pipeline`
hermes desktop                      # → pick `invoice-tracker` as a chat persona (or: hermes dashboard)
```

The zero-build web UI (`python3 webui/serve.py`) also lists this agent automatically. See
[ARCHITECTURE.md](ARCHITECTURE.md) §2 for the full exposure model.
