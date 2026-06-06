#!/usr/bin/env bash
# seo-tester, hybrid SEO checker: deterministic objective checks in code (no model
# counting), model judges only the 2 subjective checks, then a deterministic merge.
# Emits one JSON object {"checks":[…],"summary":{…}}. Pipe to jq / gate in CI.
#   cat page.md | ./run.sh | jq .
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Gather the page (args or stdin)
if [[ $# -gt 0 ]]; then PAGE="$*"; elif [[ ! -t 0 ]]; then PAGE="$(cat)"; else PAGE=""; fi

OBJ_F="$(mktemp)"; SUBJ_F="$(mktemp)"
trap 'rm -f "$OBJ_F" "$SUBJ_F"' EXIT

# 1) Objective checks, deterministic, in code.
printf '%s' "$PAGE" | python3 "$AGENT_DIR/checks.py" --objective > "$OBJ_F"

# 2) Subjective checks, the model (pipeline) judges only answerable_intro + no_keyword_stuffing.
printf '%s' "$PAGE" | "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" 2>/dev/null > "$SUBJ_F"

# 3) Merge + deterministic summary.
python3 "$AGENT_DIR/checks.py" --merge "$OBJ_F" "$SUBJ_F"
