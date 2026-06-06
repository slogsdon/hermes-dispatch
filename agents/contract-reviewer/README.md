# contract-reviewer

Does a fast risk pass over a contract or vendor agreement and returns a **severity-ranked
list of flags**, each with the quoted clause and a plain-English explanation of the risk
and what to ask for. A zero-cost first read before you forward something to a lawyer or
sign it yourself. Risk flags, not legal advice.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | none |
| **Turns** | 1 (one-shot judge) |
| **Output** | `## Verdict` / `## Findings` (`[BLOCKER\|WARN\|NOTE]`) |

## Flags it looks for

- **Limitation of liability**, missing/uncapped/asymmetric caps
- **Auto-renewal**, renewal term + the notice window to cancel
- **IP assignment**, over-broad work-product, feedback, or background-IP grabs
- **Termination**, one-sided or non-standard exit terms
- **Jurisdiction / governing law**, inconvenient venue or mandatory arbitration

## Usage

```bash
cat agreement.txt |./run.sh
pdftotext msa.pdf - |./run.sh # convert a PDF to text first
./run.sh "$(pbpaste)"
```

```
## Verdict
SIGN WITH CHANGES, liability is capped but the auto-renewal notice window is a trap.

## Findings
- [BLOCKER] IP assignment, "Client assigns all right, title and interest..." → assigns your
 background IP, not just deliverables; narrow to work product created under this SOW.
- [WARN] Auto-renewal, "renews for successive 12-month terms unless cancelled 90 days prior"
 → 90-day window is easy to miss; request 30 days and a renewal reminder clause.
- [NOTE] Governing law, "governed by the laws of Delaware" → standard; no action needed.
```

## Why this alias

Uses `max` for the same reason as `pr-reviewer` and `seo-reviewer`:
the smaller `balanced` model was caught inverting findings and miscalibrating
severity, and contract risk is high-consequence, missing an uncapped-liability or
auto-renewal trap costs real money. This is one of the agents that earns the `max` tier. When the backing model routes its thinking to a separate channel, output stays clean under the project
home's `show_reasoning: false` (`strip_reasoning`/`answer_anchor` are an inert fallback).
The trade-off is a slower cold load, worth it for a gate you actually trust.

## Scope & tuning

- Reviews **only the text you paste**. For multi-document deals (MSA + order form +
 exhibits), concatenate them first so cross-references resolve.
- The risk checklist and the `SIGN/SIGN WITH CHANGES/DO NOT SIGN` scale live in `prompt.md`.
- This is a **risk flag, not legal advice**, use it to triage and to brief a lawyer, not to
 replace one on anything that matters.

## In the Hermes desktop app

The desktop app (`hermes desktop`) and web dashboard (`hermes dashboard`) discover agents as
**profiles**, not shell wrappers. Registration is automatic, `bin/gen-profiles.sh`
auto-discovers every agent dir (any folder with `agent.yaml` + `prompt.md`), so just run it
after adding or editing an agent:

```bash
bin/gen-profiles.sh # materialize one profile per agent into ~/.hermes/profiles/
hermes profile list # confirm `contract-reviewer` appears with model `max`
hermes desktop # → pick `contract-reviewer` as a chat persona (or: hermes dashboard)
```

The zero-build web UI (`python3 webui/serve.py`) also lists this agent automatically. See
[ARCHITECTURE.md](ARCHITECTURE.md) §2 for the full exposure model.
