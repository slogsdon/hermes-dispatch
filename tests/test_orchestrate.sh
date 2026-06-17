#!/usr/bin/env bash
#
# test_orchestrate.sh — hermetic tests for lib/orchestrate.sh (the file-based state machine
# + pipeline executor). No bats/shunit2 dependency, no models: we source orchestrate.sh, then
# point REPO_ROOT / RUN_ROOT at a throwaway sandbox with a fake stdin→stdout agent, so the
# whole pipeline runs deterministically offline.
#
# Run: tests/test_orchestrate.sh   (exit 0 = all pass, nonzero = failures)
#
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/orchestrate.sh"

# Sourcing orchestrate.sh enables `set -euo pipefail` in THIS shell; turn errexit back off so a
# failing assertion doesn't abort the run.
# shellcheck source=/dev/null
source "$LIB"
set +e +u

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

# --- Isolated sandbox: override the globals orchestrate.sh resolved at source time ----------
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
REPO_ROOT="$SANDBOX"
RUN_ROOT="$SANDBOX/run"
# dispatch resolves agents at $REPO_ROOT/agents/<name>/run.sh, so the fake agent lives under agents/.
mkdir -p "$RUN_ROOT" "$SANDBOX/pipelines" "$SANDBOX/agents/fakeagent"

# Fake agent: reads stdin, prefixes it — proves the read→agent→write task-passing contract.
cat > "$SANDBOX/agents/fakeagent/run.sh" <<'AGENT'
#!/usr/bin/env bash
printf 'OUT:'; cat
AGENT
chmod +x "$SANDBOX/agents/fakeagent/run.sh"

cat > "$SANDBOX/pipelines/t.json" <<'PIPE'
{ "name": "t-pipeline",
  "steps": [ { "id": "s1", "agent": "fakeagent", "reads": "input", "writes": "out", "format": "md" } ] }
PIPE

cat > "$SANDBOX/pipelines/gated.json" <<'PIPE'
{ "name": "gated-pipeline",
  "steps": [
    { "id": "g1", "type": "gate", "gate": "approve-me" },
    { "id": "s2", "agent": "fakeagent", "reads": "input", "writes": "out", "format": "md" } ] }
PIPE

echo "== state_* helpers =="
RD="$(state_init demo)"
eq "state_init creates dir"        "$([ -d "$RD" ] && echo y)" "y"
eq "state_init status=running"     "$(jq -r .status "$RD/state.json")" "running"
eq "state_init pipeline set"       "$(jq -r .pipeline "$RD/state.json")" "demo"
eq "state_init keys empty"         "$(jq -r '.keys|length' "$RD/state.json")" "0"

printf 'hello world' > "$RD/input.txt"
state_put_key "$RD" input - input.txt
eq "state_put_key file"            "$(jq -r '.keys.input.file' "$RD/state.json")" "input.txt"
eq "state_put_key bytes"           "$(jq -r '.keys.input.bytes' "$RD/state.json")" "11"
eq "state_put_key agent null"      "$(jq -r '.keys.input.agent' "$RD/state.json")" "null"
eq "state_key_file abs path"       "$(state_key_file "$RD" input)" "$RD/input.txt"
eq "state_key_file missing empty"  "$(state_key_file "$RD" nope)" ""

state_step_start "$RD" st1 fakeagent input out
eq "step_start status running"     "$(jq -r '.steps[0].status' "$RD/state.json")" "running"
state_step_done "$RD" st1 0 out.md
eq "step_done exit0 -> done"       "$(jq -r '.steps[0].status' "$RD/state.json")" "done"
eq "state_step_status last=done"   "$(state_step_status "$RD" st1)" "done"

state_step_start "$RD" st2 fakeagent input out
state_step_done "$RD" st2 1 out.md
eq "step_done exit1 -> error"      "$(jq -r '.steps[] | select(.id=="st2") | .status' "$RD/state.json")" "error"

state_set_routing "$RD" '{"route":"project","priority":"now"}'
eq "state_set_routing stored"      "$(jq -r '.routing.route' "$RD/state.json")" "project"

echo "== pipeline_resolve =="
eq "resolve by .name"              "$(pipeline_resolve t-pipeline)" "$SANDBOX/pipelines/t.json"
eq "resolve by filename stem"      "$(pipeline_resolve gated)" "$SANDBOX/pipelines/gated.json"
pipeline_resolve does-not-exist >/dev/null 2>&1; eq "resolve unknown -> rc1" "$?" "1"

echo "== pipeline_run (offline, fake agent) =="
RD2="$(state_init t-pipeline)"
printf 'hello' > "$RD2/input.txt"; state_put_key "$RD2" input - input.txt
pipeline_run "$RD2" "$SANDBOX/pipelines/t.json" >/dev/null 2>&1
eq "pipeline status complete"      "$(jq -r .status "$RD2/state.json")" "complete"
eq "writes key registered"         "$(jq -r '.keys.out.file' "$RD2/state.json")" "out.md"
eq "agent output captured"         "$(cat "$RD2/out.md")" "OUT:hello"
eq "step recorded done"            "$(jq -r '.steps[0].status' "$RD2/state.json")" "done"

echo "== pipeline_run gate halts, resume continues =="
RD3="$(state_init gated-pipeline)"
printf 'data' > "$RD3/input.txt"; state_put_key "$RD3" input - input.txt
pipeline_run "$RD3" "$SANDBOX/pipelines/gated.json" >/dev/null 2>&1
eq "gate -> paused"                "$(jq -r .status "$RD3/state.json")" "paused"
eq "agent step NOT run yet"        "$(jq -r '.keys.out.file // "none"' "$RD3/state.json")" "none"
pipeline_run "$RD3" "$SANDBOX/pipelines/gated.json" 1 >/dev/null 2>&1   # resume=1
eq "resume -> complete"            "$(jq -r .status "$RD3/state.json")" "complete"
eq "resume ran the agent"          "$(cat "$RD3/out.md")" "OUT:data"

echo "== missing input key is a hard error =="
RD4="$(state_init t-pipeline)"
pipeline_run "$RD4" "$SANDBOX/pipelines/t.json" >/dev/null 2>&1
eq "no input -> error status"      "$(jq -r .status "$RD4/state.json")" "error"

echo ""
printf 'orchestrate: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
