#!/usr/bin/env bash
#
# run-pipeline.sh, run a named pipeline end to end over the shared state store.
#
#   bin/run-pipeline.sh <pipeline-name> "<input>"
#   echo "<input>" | bin/run-pipeline.sh <pipeline-name>
#   bin/run-pipeline.sh --resume <run-id>          # continue past an approved gate
#
# <pipeline-name> matches a definition in pipelines/ by its .name (e.g. "gtm-pipeline")
# or by filename stem (e.g. "gtm"). The script creates ./run/<run-id>/, seeds the raw
# input as the "input" key, then walks the steps, each agent reads the previous step's
# key and writes its own. Final state + payloads live in the run dir.
#
# A pipeline with a human gate (type: gate/manual/decision — see pipelines/dev-workflow.json)
# HALTS at the first such step with status "paused". After a human approves it, continue with
# `--resume <run-id>`: completed steps are skipped, the gate is marked approved, and the rest
# of the pipeline runs through WITHOUT stopping.
#
# Env:
#   HERMES_DRY_RUN=1   agents print their composed hermes command instead of calling a
#                      model, use this to verify pipeline plumbing without GPU/RAM cost.
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/orchestrate.sh
source "$LIB_DIR/orchestrate.sh"

# --- Resume mode: bin/run-pipeline.sh --resume <run-id> ----------------------------------
if [ "${1:-}" = "--resume" ]; then
  RUN_ID="${2:?usage: run-pipeline.sh --resume <run-id>}"
  RUN_DIR="$REPO_ROOT/run/$RUN_ID"
  [ -f "$RUN_DIR/state.json" ] || { echo "run-pipeline: no run '$RUN_ID' under run/" >&2; exit 1; }
  DEF="$(pipeline_resolve "$(jq -r .pipeline "$RUN_DIR/state.json")")" || {
    echo "run-pipeline: cannot resolve the pipeline for run '$RUN_ID'" >&2; exit 1; }
  pipeline_run "$RUN_DIR" "$DEF" 1
  FINAL_KEY="$(jq -r '.steps[-1].writes // empty' "$DEF")"
  FINAL_FILE="$(state_key_file "$RUN_DIR" "$FINAL_KEY")"
  [ -n "$FINAL_FILE" ] && cat "$FINAL_FILE"
  exit 0
fi
# -----------------------------------------------------------------------------------------

PIPELINE="${1:?usage: run-pipeline.sh <pipeline-name> [input]  |  --resume <run-id>}"; shift || true

DEF="$(pipeline_resolve "$PIPELINE")" || {
  echo "run-pipeline: no pipeline matching '$PIPELINE' in pipelines/" >&2; exit 1; }

# Gather input: CLI args > piped stdin.
INPUT=""
if [ "$#" -gt 0 ]; then INPUT="$*"
elif [ ! -t 0 ];  then INPUT="$(cat)"; fi
[ -n "$INPUT" ] || { echo "run-pipeline: no input (pass as arg or pipe via stdin)" >&2; exit 1; }

RUN_DIR="$(state_init "$(jq -r .name "$DEF")")"
printf '%s' "$INPUT" > "$RUN_DIR/input.txt"
state_put_key "$RUN_DIR" "input" "-" "input.txt"

pipeline_run "$RUN_DIR" "$DEF"

# Echo the final step's payload to stdout so the script composes in a shell.
FINAL_KEY="$(jq -r '.steps[-1].writes' "$DEF")"
FINAL_FILE="$(state_key_file "$RUN_DIR" "$FINAL_KEY")"
[ -n "$FINAL_FILE" ] && cat "$FINAL_FILE"
