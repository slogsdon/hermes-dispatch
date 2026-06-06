# blog-drafter

First-draft generator for the blog/content pipeline. Feed it an outline or notes; it
returns structurally sound, technically accurate Markdown prose for a human + the
`humanize`/`ms-style-pass` skills to polish.

| | |
|---|---|
| **Alias** | `pipeline` → `lfm2:24b` (14.4 GB) |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | Markdown prose, no preamble |

## Usage

```bash
# Inline brief:
./run.sh "Draft the intro section for a post on minimal local agents in Hermes. \
~250 words. Hook on 'you don't need a framework, you need five flags.'"

# From an outline file:
cat post-outline.md | ./run.sh > draft.md
```

## Why this alias

`pipeline` (lfm2:24b) is the fast, **no-thinking** structured slot. It replaced `write`
(gpt-oss:20b) here because gpt-oss is a reasoning model that prepends a `┌─ Reasoning` block
to stdout, and blog prose has no fixed heading to anchor a clean strip on, whereas
`pipeline` emits clean output directly. Per Shane's LiteLLM benchmark, `pipeline` is ~6.8×
faster than `write` with comparable quality. `--ignore-rules` is deliberately on so the
draft is **not** colored by the vault persona/skill injection; voice is set in the prompt
and refined downstream. (Want gpt-oss's reasoning-channel composition? Set `alias: write`, 
output will carry a reasoning block that needs manual trimming.)

## Pipeline fit

This is the *draft* stage only. The intended flow:

```
blog-drafter  →  humanize (Shane's voice)  →  ms-style-pass  →  publish-post
```

The prompt intentionally avoids the AI-tell patterns (staccato fragments, colon-reveals,
em-dash lists) that the `humanize` skill exists to strip, less to undo later.

## Tuning

- Always give a target length; the model otherwise over-writes.
- `[TK: …]` markers flag missing facts, grep for `TK` before publishing.
- For the genuinely hard, long-context synthesis pieces, try `alias: quality`.
