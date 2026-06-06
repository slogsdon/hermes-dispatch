# blog-drafter

First-draft generator for the blog/content pipeline. Feed it an outline or notes; it
returns structurally sound, technically accurate Markdown prose for a human + the
`humanize`/`ms-style-pass` skills to polish.

| | |
|---|---|
| **Alias** | `writing` |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | Markdown prose, no preamble |

## Usage

```bash
# Inline brief:
./run.sh "Draft the intro section for a post on minimal local agents in Hermes. \
~250 words. Hook on 'you don't need a framework, you need five flags.'"

# From an outline file:
cat post-outline.md |./run.sh > draft.md
```

## Why this alias

Blog drafting is composition: tone, flow, paragraph structure. That is the `writing`
role, not the fast `structured` role meant for JSON and extraction. Prefer a backing
model with no separate reasoning channel, so the draft is clean prose with no
`┌─ Reasoning` block to strip. `--ignore-rules` is deliberately on so the draft is
**not** colored by any vault persona or skill injection; voice is set in the prompt and
refined downstream.

## Pipeline fit

This is the *draft* stage only. The intended flow:

```
blog-drafter → humanize (a voice) → ms-style-pass → publish-post
```

The prompt intentionally avoids the AI-tell patterns (staccato fragments, colon-reveals,
em-dash lists) that the `humanize` skill exists to strip, less to undo later.

## Tuning

- Always give a target length; the model otherwise over-writes.
- `[TK: …]` markers flag missing facts, grep for `TK` before publishing.
- For the genuinely hard, long-context synthesis pieces, try `alias: max`.
