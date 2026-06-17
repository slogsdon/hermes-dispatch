#!/usr/bin/env bash
#
# orchestrate.sh — shared file-based state + pipeline executor for hermes-agents.
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

# _sj <run_dir> <jq-filter> [jq-args...] — atomically transform state.json in place.
_sj() {
  local rd="$1"; shift
  local sf="$rd/state.json" tmp
  tmp="$(mktemp "$rd/.state.XXXXXX")"
  jq "$@" "$sf" > "$tmp" && mv "$tmp" "$sf"
}

# state_init <pipeline> — create a fresh run dir, write skeleton state.json, echo run_dir.
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

# state_put_key <run_dir> <key> <agent|-> <file> — register a payload file under a key.
# The file must already exist in <run_dir>. Pass "-" for agent when there's no producer.
state_put_key() {
  local rd="$1" key="$2" agent="$3" file="$4" bytes now
  bytes="$(wc -c < "$rd/$file" | tr -d ' ')"; now="$(_now)"
  local agent_json='null'; [ "$agent" != "-" ] && agent_json="\"$agent\""
  _sj "$rd" --arg k "$key" --arg f "$file" --argjson a "$agent_json" \
            --argjson b "$bytes" --arg t "$now" \
    '.keys[$k] = {file:$f, agent:$a, bytes:$b, updated_at:$t} | .updated_at = $t'
}

# state_key_file <run_dir> <key> — echo absolute path to a key's payload (empty if absent).
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

# pipeline_resolve <name-or-file> — echo the path to a pipeline definition file.
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

# state_step_status <run_dir> <id> — echo the LAST recorded status for a step id (empty if none).
state_step_status() {
  local rd="$1" id="$2"
  jq -r --arg id "$id" '[.steps[] | select(.id==$id)] | last | .status // empty' "$rd/state.json"
}

# pipeline_test_loop <run_dir> <step-json> — the validation revision loop.
# Extracts the generated code + tests onto disk (run/<id>/workspace/), runs the deterministic
# test-runner (unit → integration → playwright, ground truth from exit codes), and on failure
# feeds the REAL failures back to the fixer agent (code-generator, REFINE mode) for a revision,
# re-running until green or until max_cycles. Records per-cycle, per-layer results and the
# revision count in state.json. Returns: 0 = validated (green) · 2 = escalate to human (still
# red after max_cycles, pipeline pauses) · 1 = hard error.
pipeline_test_loop() {
  local rd="$1" step="$2"
  local id agent code_key tests_key writes maxc ws cycle results ok code_file tests_file infile fixfile
  id="$(echo "$step"      | jq -r .id)"
  agent="$(echo "$step"   | jq -r .agent)"
  code_key="$(echo "$step"| jq -r .reads)"
  tests_key="$(echo "$step"| jq -r '.tests // empty')"
  writes="$(echo "$step"  | jq -r .writes)"
  maxc="$(echo "$step"    | jq -r '.max_cycles // 5')"
  # Workspace placement. Default: under the run dir. When sandboxing the validate loop
  # (HERMES_SANDBOX_USER set), run untrusted model code in a world-traversable throwaway base
  # OUTSIDE the user's home tree, and grant ONLY the sandbox user access to that workspace
  # (with inheritance, so files re-extracted on later cycles are covered too).
  local sbase
  if [ -n "${HERMES_SANDBOX_USER:-}" ]; then
    sbase="${HERMES_SANDBOX_BASE:-/Users/Shared/hermes-agents-sandbox}"
    mkdir -p "$sbase"; chmod 0711 "$sbase" 2>/dev/null || true
    ws="$sbase/$(basename "$rd")"
  else
    ws="$rd/workspace"
  fi
  rm -rf "$ws"; mkdir -p "$ws"
  if [ -n "${HERMES_SANDBOX_USER:-}" ]; then
    chmod +a "${HERMES_SANDBOX_USER} allow read,write,execute,delete,add_file,add_subdirectory,file_inherit,directory_inherit" "$ws" 2>/dev/null || true
  fi

  code_file="$(state_key_file "$rd" "$code_key")"
  [ -n "$code_file" ] || { echo "✗ test-loop '$id': code key '$code_key' missing" >&2; state_set_status "$rd" error; return 1; }

  # Dry-run: prove the wiring without spinning the loop on non-code echo output.
  if [ "${HERMES_DRY_RUN:-}" = "1" ]; then
    state_step_start "$rd" "$id" "$agent" "$code_key" "$writes"
    cp "$code_file" "$rd/$writes.md" 2>/dev/null || printf '(dry-run validated)\n' > "$rd/$writes.md"
    state_put_key  "$rd" "$writes" "$agent" "$writes.md"
    state_step_done "$rd" "$id" 0 "$writes.md"
    echo "  ⟳ $id: DRY-RUN — skipping real test execution (plumbing only)" >&2
    return 0
  fi

  python3 "$ORCH_LIB_DIR/extract_files.py" "$ws" "$code_file" >/dev/null 2>>"$rd/$id.stderr" || true
  tests_file=""
  if [ -n "$tests_key" ]; then
    tests_file="$(state_key_file "$rd" "$tests_key")"
    [ -n "$tests_file" ] && { python3 "$ORCH_LIB_DIR/extract_files.py" "$ws" "$tests_file" >/dev/null 2>>"$rd/$id.stderr" || true; }
  fi

  state_step_start "$rd" "$id" "$agent" "$code_key" "$writes"
  cycle=0
  while : ; do
    echo "  ⟳ $id: test cycle $cycle (max $maxc) — workspace $ws" >&2
    results="$("$ORCH_LIB_DIR/test-runner.sh" "$ws" 2>>"$rd/$id.stderr")" || true
    [ -n "$results" ] || results='{"ok":false,"stack":"unknown","layers":{}}'
    # record this cycle's per-layer results + the running revision count
    _sj "$rd" --arg id "$id" --argjson c "$cycle" --argjson r "$results" --arg t "$(_now)" \
      '(.steps[] | select(.id==$id and .status=="running"))
         |= (.test_cycles = ((.test_cycles // []) + [{cycle:$c, ok:$r.ok, layers:$r.layers}])
             | .revision_cycles = $c)
       | .updated_at = $t'
    ok="$(printf '%s' "$results" | jq -r '.ok' 2>/dev/null || echo false)"

    if [ "$ok" = "true" ]; then
      cp "$code_file" "$rd/$writes.md"
      state_put_key  "$rd" "$writes" "$agent" "$writes.md"
      state_step_done "$rd" "$id" 0 "$writes.md"
      echo "  ✓ $id: tests GREEN after $cycle revision(s)" >&2
      return 0
    fi
    if [ "$cycle" -ge "$maxc" ]; then
      # When most tests pass and only a small, STABLE set keeps failing across cycles, the
      # likeliest cause is an INCORRECT TEST (e.g. a wrong hardcoded expected value), not code
      # the model can't write. Surface that to the human gate instead of just "still red".
      local up uf suspects=""
      up="$(printf '%s' "$results" | jq -r '.layers.unit.passed // 0')"
      uf="$(printf '%s' "$results" | jq -r '.layers.unit.failed // 0')"
      if [ "${up:-0}" -gt "${uf:-0}" ] && [ "${uf:-0}" -le 3 ] && [ "${uf:-0}" -gt 0 ]; then
        suspects="$(printf '%s' "$results" | jq -r '.layers.unit.excerpt // ""' \
          | grep -oE 'FAILED [^ ]+|DID NOT RAISE|AssertionError[^|]*' | grep -oE 'FAILED [^ ]+' | sed 's/^FAILED //' | sort -u | paste -sd', ' -)"
      fi
      _sj "$rd" --arg id "$id" --arg t "$(_now)" --arg s "$suspects" \
        '(.steps[] | select(.id==$id and .status=="running"))
           |= (.status="needs-human" | .ended_at=$t | .suspected_bad_tests=$s) | .updated_at=$t'
      state_set_status "$rd" "paused"
      echo "⏸ $id: tests still RED after $maxc revision cycle(s) — escalating to human review (see $rd/$id.stderr and state.json test_cycles)" >&2
      if [ -n "$suspects" ]; then
        echo "   ⚠ ${up} passing / ${uf} failing held steady — the persistent failure(s) may be INCORRECT TESTS, not bad code. Review the test before the code: $suspects" >&2
      fi
      return 2
    fi

    # Feed the real failures back to the fixer (REFINE): code + tests + failing-layer excerpts.
    infile="$rd/.fix.$id"
    {
      printf '===== code =====\n'; cat "$code_file"; printf '\n\n'
      [ -n "$tests_file" ] && { printf '===== tests =====\n'; cat "$tests_file"; printf '\n\n'; }
      printf '===== test failures (cycle %s) — make these pass, do not weaken the tests =====\n' "$cycle"
      printf '%s' "$results" | jq -r '.layers | to_entries[]
        | select(.value.present and (.value.status!="pass"))
        | "## \(.key) — \(.value.status) (cmd: \(.value.cmd))\n\(.value.excerpt)\n"' 2>/dev/null || true
    } > "$infile"
    fixfile="$rd/$writes.cycle$((cycle + 1)).md"
    if ! "$REPO_ROOT/agents/$agent/run.sh" < "$infile" > "$fixfile" 2>>"$rd/$id.stderr"; then
      state_step_done "$rd" "$id" 1 "$fixfile"; state_set_status "$rd" error
      echo "✗ $id: fixer agent '$agent' failed on cycle $((cycle + 1)) — see $rd/$id.stderr" >&2
      return 1
    fi
    code_file="$fixfile"
    python3 "$ORCH_LIB_DIR/extract_files.py" "$ws" "$code_file" >/dev/null 2>>"$rd/$id.stderr" || true
    cycle=$((cycle + 1))
  done
}

# pipeline_run <run_dir> <def_file> [resume] — execute every step in order, threading state.
# Each agent step: read keys[<reads>] → pipe to <agent>/run.sh → capture stdout to keys[<writes>].
# `reads` may be a single key OR an array of keys (concatenated with labeled separators, so a
# step like `refine` can consume `[code, review]` at once). Honors HERMES_DRY_RUN (the agent
# prints its composed command instead of calling a model).
#
# Human-checkpoint steps carry `type` ∈ {gate, manual, decision} (missing ⇒ agent). On a fresh
# run the first such step HALTS the pipeline with status "paused" — these are the genuine human
# decision points (e.g. "approve this spec before we write code"). Pass resume=1 (via
# `run-pipeline.sh --resume <run-id>`) to continue: already-"done" steps are skipped, the paused
# gate is marked approved, and execution runs ON through the remaining AGENT steps — code
# generation, validation, refine, ship — WITHOUT stopping. So the only stop in the whole
# idea→spec→code→validated-solution cycle is the one spec-approval gate.
pipeline_run() {
  local rd="$1" def="$2" resume="${3:-0}" n i
  n="$(jq -r '.steps | length' "$def")"
  echo "▶ pipeline '$(jq -r .name "$def")' — $n step(s) — run $(basename "$rd")$( [ "$resume" = 1 ] && printf ' [resume]')" >&2
  [ "$resume" = 1 ] && state_set_status "$rd" running
  i=0
  while [ "$i" -lt "$n" ]; do
    local step id agent writes fmt typ label cur reads_disp infile outfile k kf tl cmd reads_key tool_in
    step="$(jq -c ".steps[$i]" "$def")"
    id="$(echo "$step"   | jq -r .id)"
    agent="$(echo "$step"| jq -r .agent)"
    writes="$(echo "$step"| jq -r .writes)"
    fmt="$(echo "$step"  | jq -r '.format // "md"')"
    typ="$(echo "$step"  | jq -r '.type // "agent"')"
    cur="$(state_step_status "$rd" "$id")"

    # --- Validation revision loop: deterministic test execution + auto-fix -----------------
    if [ "$typ" = "test-loop" ]; then
      if [ "$cur" = "done" ]; then i=$((i + 1)); continue; fi
      if pipeline_test_loop "$rd" "$step"; then tl=0; else tl=$?; fi
      if   [ "$tl" -eq 2 ]; then return 0          # escalated to human → halt cleanly (paused)
      elif [ "$tl" -ne 0 ]; then return 1; fi       # hard error
      i=$((i + 1)); continue
    fi

    # --- Tool steps (deterministic lib scripts; no model) ----------------------------------
    # A `tool` step runs a repo-relative executable (`.cmd`) with the `reads` key piped to
    # stdin and stdout captured to the `writes` key — same task-passing contract as an agent,
    # but deterministic (like test-loop). Used by the LinkedIn GTM enrich step
    # (lib/apollo-enrich.sh), which itself exits 0 even without a key, so it never breaks a run.
    if [ "$typ" = "tool" ]; then
      if [ "$cur" = "done" ]; then i=$((i + 1)); continue; fi
      cmd="$(echo "$step" | jq -r '.cmd // empty')"
      [ -n "$cmd" ] && [ -x "$REPO_ROOT/$cmd" ] || {
        echo "✗ step '$id': tool cmd '${cmd:-?}' not found/executable" >&2
        state_set_status "$rd" error; return 1; }
      reads_key="$(echo "$step" | jq -r .reads)"
      tool_in="$(state_key_file "$rd" "$reads_key")"
      if [ -z "$tool_in" ] || [ ! -f "$tool_in" ]; then
        echo "✗ step '$id': input key '$reads_key' not in state" >&2; state_set_status "$rd" error; return 1; fi
      outfile="$writes.$fmt"
      state_step_start "$rd" "$id" "$cmd" "$reads_key" "$writes"
      if [ "${HERMES_DRY_RUN:-}" = "1" ]; then
        printf '(dry-run tool: %s < %s)\n' "$cmd" "$reads_key" > "$rd/$outfile"
        state_put_key  "$rd" "$writes" "$cmd" "$outfile"
        state_step_done "$rd" "$id" 0 "$outfile"
        echo "  ⚙ $id: DRY-RUN tool $cmd ($reads_key → $writes)" >&2
        i=$((i + 1)); continue
      fi
      echo "  ⚙ $id: $cmd  ($reads_key → $writes)" >&2
      if "$REPO_ROOT/$cmd" < "$tool_in" > "$rd/$outfile" 2> "$rd/$id.stderr"; then
        state_put_key  "$rd" "$writes" "$cmd" "$outfile"
        state_step_done "$rd" "$id" 0 "$outfile"
      else
        local ec=$?
        state_step_done "$rd" "$id" "$ec" "$outfile"
        state_set_status "$rd" error
        echo "✗ step '$id' (tool $cmd) failed (exit $ec) — see $rd/$id.stderr" >&2
        return 1
      fi
      i=$((i + 1)); continue
    fi

    # --- Human-checkpoint steps (gate / manual / decision) ---------------------------------
    if [ "$typ" != "agent" ]; then
      label="$(echo "$step" | jq -r '.gate // .note // .id')"
      if [ "$cur" = "done" ]; then i=$((i + 1)); continue; fi          # approved on a prior resume
      if [ "$resume" = 1 ] && [ "$cur" = "paused" ]; then              # human approved → continue past it
        _sj "$rd" --arg id "$id" --arg t "$(_now)" \
          '(.steps[] | select(.id==$id and .status=="paused")) |= (.status="done" | .ended_at=$t) | .updated_at=$t'
        echo "  ✓ gate '$id' approved — continuing" >&2
        i=$((i + 1)); continue
      fi
      echo "  ⏸ $id [$typ]: $label" >&2                                # fresh encounter → halt for the human
      _sj "$rd" --arg id "$id" --arg ty "$typ" --arg g "$label" --arg t "$(_now)" \
        '.steps += [{id:$id, agent:("(" + $ty + ")"), reads:null, writes:null,
                     status:"paused", exit_code:null, started_at:$t, ended_at:$t,
                     output_file:null, gate:$g}] | .updated_at = $t'
      state_set_status "$rd" "paused"
      echo "⏸ paused at '$id' ($typ). Approve, then continue with:  bin/run-pipeline.sh --resume $(basename "$rd")" >&2
      return 0
    fi

    # --- Agent steps -----------------------------------------------------------------------
    if [ "$cur" = "done" ]; then i=$((i + 1)); continue; fi            # already ran (resume) → skip

    # Resolve input. `reads` is a single key, or an array concatenated with labeled separators.
    if echo "$step" | jq -e '(.reads|type)=="array"' >/dev/null; then
      reads_disp="$(echo "$step" | jq -r '.reads | join("+")')"
      infile="$rd/.in.$id"; : > "$infile"
      for k in $(echo "$step" | jq -r '.reads[]'); do
        kf="$(state_key_file "$rd" "$k")"
        if [ -z "$kf" ] || [ ! -f "$kf" ]; then
          echo "✗ step '$id': input key '$k' not in state" >&2; state_set_status "$rd" error; return 1; fi
        printf '===== %s =====\n' "$k" >> "$infile"; cat "$kf" >> "$infile"; printf '\n\n' >> "$infile"
      done
    else
      reads_disp="$(echo "$step"| jq -r .reads)"
      infile="$(state_key_file "$rd" "$reads_disp")"
      if [ -z "$infile" ] || [ ! -f "$infile" ]; then
        echo "✗ step '$id': input key '$reads_disp' not in state" >&2; state_set_status "$rd" error; return 1; fi
    fi
    [ -x "$REPO_ROOT/agents/$agent/run.sh" ] || {
      echo "✗ step '$id': $agent/run.sh not found/executable" >&2
      state_set_status "$rd" error; return 1; }

    outfile="$writes.$fmt"
    echo "  → $id: $agent  ($reads_disp → $writes)" >&2
    state_step_start "$rd" "$id" "$agent" "$reads_disp" "$writes"
    if "$REPO_ROOT/agents/$agent/run.sh" < "$infile" > "$rd/$outfile" 2> "$rd/$id.stderr"; then
      state_put_key  "$rd" "$writes" "$agent" "$outfile"
      state_step_done "$rd" "$id" 0 "$outfile"
    else
      local ec=$?
      state_step_done "$rd" "$id" "$ec" "$outfile"
      state_set_status "$rd" error
      echo "✗ step '$id' ($agent) failed (exit $ec) — see $rd/$id.stderr" >&2
      return 1
    fi
    i=$((i + 1))
  done
  state_set_status "$rd" complete
  echo "✓ complete — $rd" >&2
}
