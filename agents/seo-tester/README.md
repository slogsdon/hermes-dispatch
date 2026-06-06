# seo-tester

Runs a fixed battery of on-page SEO/AEO checks and emits **one JSON object** with per-check
pass/fail/warn + a summary verdict. The machine-readable counterpart to `seo-reviewer`, 
drop it in a content CI gate or batch it over a site.

| | |
|---|---|
| **Model** | `pipeline` → `lfm2:24b` (subjective checks only) + deterministic code |
| **Tools** | none |
| **Output** | `{"checks":[…],"summary":{…}}` minified JSON |

## Usage

```bash
cat page.md | ./run.sh | jq .

# Gate in a script: fail the build if verdict != pass
v=$(cat page.md | ./run.sh | jq -r '.summary.verdict')
[[ "$v" == "pass" ]] || { echo "SEO gate failed"; exit 1; }
```

Provide the page as labelled lines (`Target keyword:`, `Title:`, `Meta:`, `H1:`), `##`
subheadings, and body prose.

## Hybrid design (objective in code, subjective by model)

Earlier this agent was pure-LLM and **fabricated char counts** (it scored a 218-char meta as
"158/pass") and produced summary tallies that didn't match its own checks. So the work is
split:

- **Objective checks, deterministic, in [`checks.py`](checks.py):** `title_length`,
  `meta_length`, `single_h1`, `keyword_in_title`, `keyword_in_h1`, `keyword_early`,
  `has_subheadings`, `internal_link`. The model never counts.
- **Subjective checks, the model judges only these two:** `answerable_intro`,
  `no_keyword_stuffing` (via [`prompt.md`](prompt.md), returning a tiny JSON).
- **Merge + summary, deterministic:** [`run.sh`](run.sh) merges both and recomputes the
  `summary` counts in code, so the tally always reconciles with the checks array.

Keyword matching is forgiving: exact phrase → `pass`, ≥60% of keyword tokens present →
`warn` (close variant), otherwise `fail`. `internal_link` passes only on a real Markdown
link or URL (link-*intent* text like "see our guide" is a `warn`).

## Tuning

- Edit the thresholds/checks in `checks.py`; edit the two subjective checks in `prompt.md`.
- `HERMES_DRY_RUN` doesn't apply here (this agent runs a code+model pipeline, not a single
  `hermes` call).
