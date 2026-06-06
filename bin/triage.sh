#!/usr/bin/env bash
#
# triage.sh, the standard pipeline entry point.
#
#   bin/triage.sh "<raw input>"
#   echo "<raw input>" | bin/triage.sh
#
# Flow: create a run → run triage-router over the raw input → record the routing
# decision into state.json (.routing) → map it to a pipeline via pipelines/routes.json
# → run that pipeline IN THE SAME RUN, so the classification and the work share one
# state dir. This is the front door: callers don't pick the pipeline, the router does.
#
# triage-router emits inbox-routing enums (category/priority/route), not pipeline names,
# so routes.json is the adapter (lookup order: by_route → by_category → default).
#
# Env:
#   TRIAGE_DECISION_JSON='{"category":"task","route":"project",...}'
#       Skip the classifier and use this decision verbatim. Use it to pre-route when you
#       already know the category, or to test routing/state logic without loading a model.
#   HERMES_DRY_RUN=1
#       Downstream pipeline agents print their composed command instead of calling a
#       model. NOTE: this also makes triage-router print a command (not JSON), so pair it
#       with TRIAGE_DECISION_JSON for a fully model-free plumbing test.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/orchestrate.sh
source "$LIB_DIR/orchestrate.sh"
ROUTES="$REPO_ROOT/pipelines/routes.json"

# Gather input.
INPUT=""
if [ "$#" -gt 0 ]; then INPUT="$*"
elif [ ! -t 0 ];  then INPUT="$(cat)"; fi
[ -n "$INPUT" ] || { echo "triage: no input (pass as arg or pipe via stdin)" >&2; exit 1; }

RUN_DIR="$(state_init "triage")"
printf '%s' "$INPUT" > "$RUN_DIR/input.txt"
state_put_key "$RUN_DIR" "input" "-" "input.txt"

# 1) Classify. triage-router writes one minified-JSON line (or use the override).
state_step_start "$RUN_DIR" "triage" "triage-router" "input" "triage"
if [ -n "${TRIAGE_DECISION_JSON:-}" ]; then
  echo "▶ triage: using TRIAGE_DECISION_JSON override (classifier skipped)" >&2
  printf '%s' "$TRIAGE_DECISION_JSON" > "$RUN_DIR/triage.json"
  state_put_key   "$RUN_DIR" "triage" "triage-router" "triage.json"
  state_step_done "$RUN_DIR" "triage" 0 "triage.json"
else
  echo "▶ triage: classifying…" >&2
  if "$REPO_ROOT/triage-router/run.sh" < "$RUN_DIR/input.txt" \
        > "$RUN_DIR/triage.json" 2> "$RUN_DIR/triage.stderr"; then
    state_put_key   "$RUN_DIR" "triage" "triage-router" "triage.json"
    state_step_done "$RUN_DIR" "triage" 0 "triage.json"
  else
    ec=$?; state_step_done "$RUN_DIR" "triage" "$ec" "triage.json"
    state_set_status "$RUN_DIR" error
    echo "✗ triage-router failed (exit $ec), see $RUN_DIR/triage.stderr" >&2; exit 1
  fi
fi

# Validate the decision is JSON; record it on .routing.
DECISION="$(cat "$RUN_DIR/triage.json")"
if ! echo "$DECISION" | jq -e . >/dev/null 2>&1; then
  echo "✗ triage-router did not emit valid JSON: $DECISION" >&2
  state_set_status "$RUN_DIR" error; exit 1
fi
CATEGORY="$(echo "$DECISION" | jq -r '.category // empty')"
ROUTE="$(echo    "$DECISION" | jq -r '.route // empty')"

# 2) Map decision → pipeline (by_route → by_category → default).
PIPELINE="$(jq -r --arg r "$ROUTE" --arg c "$CATEGORY" \
  '.by_route[$r] // .by_category[$c] // .default' "$ROUTES")"
[ -n "$PIPELINE" ] && [ "$PIPELINE" != "null" ] || {
  echo "✗ no pipeline for route='$ROUTE' category='$CATEGORY' and no default" >&2
  state_set_status "$RUN_DIR" error; exit 1; }

# Record the full routing decision (classification + chosen pipeline) into state.
state_set_routing "$RUN_DIR" "$(echo "$DECISION" | jq --arg p "$PIPELINE" '{decision:., pipeline:$p}')"
echo "▶ triage: category=$CATEGORY route=$ROUTE → pipeline '$PIPELINE'" >&2

# 3) Run the chosen pipeline in this same run dir.
DEF="$(pipeline_resolve "$PIPELINE")" || {
  echo "✗ routed pipeline '$PIPELINE' has no definition in pipelines/" >&2
  state_set_status "$RUN_DIR" error; exit 1; }
pipeline_run "$RUN_DIR" "$DEF"

FINAL_KEY="$(jq -r '.steps[-1].writes' "$DEF")"
FINAL_FILE="$(state_key_file "$RUN_DIR" "$FINAL_KEY")"
[ -n "$FINAL_FILE" ] && cat "$FINAL_FILE"
