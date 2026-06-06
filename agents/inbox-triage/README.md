# inbox-triage

Classifies a **batch** of emails (subject + snippet) into a fixed enum and, for the urgent
ones, drafts a one-sentence suggested reply, emitting **one line of minified JSON** (an
array, one object per email). The personal-productivity sibling of `triage-router`: pipe a
pasted inbox straight to `jq`.

| | |
|---|---|
| **Alias** | `pipeline` → `lfm2:24b` (14.4 GB) |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | `[{"subject","category","draft_reply"}, …]` minified JSON array |

Categories: `REPLY-TODAY` · `REPLY-THIS-WEEK` · `FYI-ONLY` · `UNSUBSCRIBE` · `DELEGATE`.
`draft_reply` is a single ready-to-send sentence for `REPLY-TODAY` items, `""` otherwise.

## Usage

```bash
# Paste a batch of subjects/snippets (one per line) and pretty-print:
./run.sh "Q3 budget sign-off, need your ok by EOD
Weekly newsletter from SomeSaaS, '7 ways to ship faster'
Can you review the vendor contract? (from legal, blocking their Friday)" | jq .
# [
#   {"subject":"Q3 budget sign-off","category":"REPLY-TODAY","draft_reply":"Approved, go ahead and proceed."},
#   {"subject":"Weekly newsletter from SomeSaaS","category":"UNSUBSCRIBE","draft_reply":""},
#   {"subject":"Review the vendor contract","category":"DELEGATE","draft_reply":""}
# ]

# Straight from the clipboard:
pbpaste | ./run.sh | jq -r '.[] | select(.category=="REPLY-TODAY") | "→ " + .draft_reply'
```

## Why this alias (not `classify`)

Same call as `triage-router`/`invoice-tracker`. The obvious pick is `classify`
(lfm2.5-thinking:1.2b), but it's a **thinking** model that streams chain-of-thought before
the JSON even with `-Q`, and its 1.2B reasoning mis-picks fields. So this agent uses
**`pipeline` (lfm2:24b)**, explicitly "fast structured tasks, *no thinking*", for clean
JSON. The whole batch comes back as a single minified array on one line, and
`parse_last_line: true` keeps only that final line as belt-and-braces against any stray
preamble.

## Desktop (Hermes app)

The desktop/dashboard discovers **profiles**, not this repo's `run.sh` agents. Register it
once (re-run after editing `prompt.md` or the model alias):

```bash
bin/gen-profiles.sh inbox-triage   # → ~/.hermes/profiles/inbox-triage/
hermes profile list                # confirm it appears (model=pipeline)
hermes desktop                     # select it as a chat persona
```

Note: the desktop runs an interactive chat; for the one-shot JSON-array contract, use
`run.sh`. See [DESKTOP_COMPAT.md](../DESKTOP_COMPAT.md) for the full discovery mechanism and
the bare-`hermes chat` caveat.

## Tuning

- The enums and the draft-reply rule live in `prompt.md`. Edit the category set there to fit
  your own triage buckets; keep the "ONE line of JSON array" contract intact.
- Want sub-second triage on small batches? Switch to `alias: classify`, `parse_last_line`
  is already on to absorb its CoT output.
- Keep batches under the real `pipeline` num_ctx (~32K). For a giant inbox, chunk it.
