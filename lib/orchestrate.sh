#!/usr/bin/env bash
#
# orchestrate.sh, shared file-based state + pipeline executor for hermes-agents.
#
# This is the project's "orchestration layer": no database, no service. A run is a
# directory under ./run/<run-id>/ holding one state.json (the index) plus one plain
# file per named key (the payloads). Agents stay pure stdin→stdout shell wrappers;
# this layer owns all state, so an agent never needs to know it's in a pipeline.
#
# state.json schema (v1)
# ----------------------
# {
#   "run_id":   "20260604-181500-12345",
#   "pipeline": "gtm-pipeline",          // or "triage" for a bare triage run
#   "status":   "running|complete|error",
#   "created_at": "2026-06-04T18:15:00Z",
#   "updated_at": "2026-06-04T18:17:42Z",
#   "steps": [                            // ordered execution log, one per agent run
#     { "id":"plan", "agent":"gtm-planner", "reads":"input", "writes":"plan",
#       "status":"pending|running|done|error", "exit_code":0,
#       "started_at":"...", "ended_at":"...", "output_file":"plan.md" }
#   ],
#   "keys": {                             // the shared named-key store (pointers, not blobs)
#     "input": { "file":"input.txt", "agent":null,        "bytes":412,  "updated_at":"..." },
#     "plan":  { "file":"plan.md",   "agent":"gtm-planner","bytes":2310, "updated_at":"..." }
#   },
#   "routing": null                       // triage decision once classified (see triage.sh)
# }
#
# Payloads live next to state.json (input.txt, plan.md, assets.md, ...). The key store
# holds only the filename + metadata, so large multi-section Markdown never has to be
# JSON-escaped. The "next agent" reads keys["<reads>"].file; the runner writes
# keys["<writes>"].file. That is the entire task-passing contract.
#
# Requires: jq. Source this file; call the state_* / pipeline_* functions.

set -euo pipefail

ORCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$ORCH_LIB_DIR")"
RUN_ROOT="$REPO_ROOT/run"

command -v jq >/dev/null 2>&1 || { echo "orchestrate: jq is required" >&2; exit 1; }

_now()    { date -u +%Y-%m-%dT%H:%M:%SZ; }
_run_id() { echo "$(date +%Y%m%d-%H%M%S)-$$$RANDOM"; }

# _sj <run_dir> <jq-filter> [jq-args...], atomically transform state.json in place.
_sj() {
  local rd="$1"; shift
  local sf="$rd/state.json" tmp
  tmp="$(mktemp "$rd/.state.XXXXXX")"
  jq "$@" "$sf" > "$tmp" && mv "$tmp" "$sf"
}

# state_init <pipeline>, create a fresh run dir, write skeleton state.json, echo run_dir.
state_init() {
  local pipeline="$1" rid rd now
  rid="$(_run_id)"; rd="$RUN_ROOT/$rid"; now="$(_now)"
  mkdir -p "$rd"
  jq -n --arg id "$rid" --arg p "$pipeline" --arg t "$now" '{
    run_id:$id, pipeline:$p, status:"running",
    created_at:$t, updated_at:$t, steps:[], keys:{}, routing:null
  }' > "$rd/state.json"
  echo "$rd"
}

# state_put_key <run_dir> <key> <agent|-> <file>, register a payload file under a key.
# The file must already exist in <run_dir>. Pass "-" for agent when there's no producer.
state_put_key() {
  local rd="$1" key="$2" agent="$3" file="$4" bytes now
  bytes="$(wc -c < "$rd/$file" | tr -d ' ')"; now="$(_now)"
  local agent_json='null'; [ "$agent" != "-" ] && agent_json="\"$agent\""
  _sj "$rd" --arg k "$key" --arg f "$file" --argjson a "$agent_json" \
            --argjson b "$bytes" --arg t "$now" \
    '.keys[$k] = {file:$f, agent:$a, bytes:$b, updated_at:$t} | .updated_at = $t'
}

# state_key_file <run_dir> <key>, echo absolute path to a key's payload (empty if absent).
state_key_file() {
  local rd="$1" key="$2" f
  f="$(jq -r --arg k "$key" '.keys[$k].file // empty' "$rd/state.json")"
  [ -n "$f" ] && echo "$rd/$f"
}

state_step_start() {
  local rd="$1" id="$2" agent="$3" reads="$4" writes="$5" now; now="$(_now)"
  _sj "$rd" --arg id "$id" --arg a "$agent" --arg r "$reads" --arg w "$writes" --arg t "$now" \
    '.steps += [{id:$id, agent:$a, reads:$r, writes:$w, status:"running",
                 exit_code:null, started_at:$t, ended_at:null, output_file:null}]
     | .updated_at = $t'
}

state_step_done() {
  local rd="$1" id="$2" ec="$3" outfile="$4" status now; now="$(_now)"
  [ "$ec" -eq 0 ] && status="done" || status="error"
  _sj "$rd" --arg id "$id" --arg s "$status" --argjson ec "$ec" --arg o "$outfile" --arg t "$now" \
    '(.steps[] | select(.id==$id and .status=="running"))
       |= (.status=$s | .exit_code=$ec | .ended_at=$t | .output_file=$o)
     | .updated_at = $t'
}

state_set_status() {
  local rd="$1" status="$2"; _sj "$rd" --arg s "$status" --arg t "$(_now)" \
    '.status = $s | .updated_at = $t'
}

state_set_routing() {
  # <run_dir> <routing-json-string>
  local rd="$1" routing="$2"; _sj "$rd" --argjson r "$routing" --arg t "$(_now)" \
    '.routing = $r | .updated_at = $t'
}

# pipeline_resolve <name-or-file>, echo the path to a pipeline definition file.
# Matches by the def's .name first, then falls back to pipelines/<name>.json.
pipeline_resolve() {
  local want="$1" f
  for f in "$REPO_ROOT"/pipelines/*.json; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "routes.json" ] && continue
    if [ "$(jq -r '.name // empty' "$f")" = "$want" ]; then echo "$f"; return 0; fi
  done
  [ -f "$REPO_ROOT/pipelines/$want.json" ] && { echo "$REPO_ROOT/pipelines/$want.json"; return 0; }
  return 1
}

# pipeline_run <run_dir> <def_file>, execute every step in order, threading state.
# Each step: read keys[<reads>] → pipe to <agent>/run.sh → capture stdout to keys[<writes>].
# Honors HERMES_DRY_RUN (the agent prints its composed command instead of calling a model).
pipeline_run() {
  local rd="$1" def="$2" n i
  n="$(jq -r '.steps | length' "$def")"
  echo "▶ pipeline '$(jq -r .name "$def")', $n step(s), run $(basename "$rd")" >&2
  i=0
  while [ "$i" -lt "$n" ]; do
    local step id agent reads writes fmt infile outfile
    step="$(jq -c ".steps[$i]" "$def")"
    id="$(echo "$step"   | jq -r .id)"
    agent="$(echo "$step"| jq -r .agent)"
    reads="$(echo "$step"| jq -r .reads)"
    writes="$(echo "$step"| jq -r .writes)"
    fmt="$(echo "$step"  | jq -r '.format // "md"')"

    infile="$(state_key_file "$rd" "$reads")"
    if [ -z "$infile" ] || [ ! -f "$infile" ]; then
      echo "✗ step '$id': input key '$reads' not in state" >&2
      state_set_status "$rd" error; return 1
    fi
    [ -x "$REPO_ROOT/agents/$agent/run.sh" ] || {
      echo "✗ step '$id': $agent/run.sh not found/executable" >&2
      state_set_status "$rd" error; return 1; }

    outfile="$writes.$fmt"
    echo "  → $id: $agent  ($reads → $writes)" >&2
    state_step_start "$rd" "$id" "$agent" "$reads" "$writes"
    if "$REPO_ROOT/agents/$agent/run.sh" < "$infile" > "$rd/$outfile" 2> "$rd/$id.stderr"; then
      state_put_key  "$rd" "$writes" "$agent" "$outfile"
      state_step_done "$rd" "$id" 0 "$outfile"
    else
      local ec=$?
      state_step_done "$rd" "$id" "$ec" "$outfile"
      state_set_status "$rd" error
      echo "✗ step '$id' ($agent) failed (exit $ec), see $rd/$id.stderr" >&2
      return 1
    fi
    i=$((i + 1))
  done
  state_set_status "$rd" complete
  echo "✓ complete, $rd" >&2
}
