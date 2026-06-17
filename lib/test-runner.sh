#!/usr/bin/env bash
#
# test-runner.sh — deterministic, ground-truth test execution for a workspace.
#
# Detects the project's stack, then runs up to three layers IN ORDER, each gated on
# the previous one passing (per the workflow: unit → integration → Playwright):
#   1. unit          2. integration          3. playwright (E2E)
#
# Pass/fail is taken from the process EXIT CODE — never from a model's claim. This is
# the same principle as seo-tester's checks.py: the model never counts. The orchestrator
# (lib/orchestrate.sh, the `test-loop` step) calls this, reads the JSON, and on failure
# feeds the captured output back to the code-gen agent for revision.
#
# Usage:   lib/test-runner.sh <workspace-dir>
# Output:  a JSON object on stdout (see SHAPE below); full per-layer logs in
#          <workspace>/.tests/<layer>.log.
#
# Env:
#   TEST_RUNNER_INSTALL=1   best-effort dependency install before running (npm/pip/composer).
#                           Default off (no network, fast); stdlib tests need nothing.
#   UNIT_CMD / INTEGRATION_CMD / PLAYWRIGHT_CMD
#                           override detection for a layer (e.g. an odd setup found by the
#                           shell-enabled test-runner AGENT). Empty string ("") = layer absent.
#
# SHAPE:
# {"ok":bool,"stack":"node|php|python|make|unknown",
#  "layers":{"unit":{...},"integration":{...},"playwright":{...}}}
# each layer: {"present":bool,"status":"pass|fail|error|absent|skipped",
#              "passed":int,"failed":int,"cmd":str,"excerpt":str}
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SELF_DIR")"
WS="${1:?usage: test-runner.sh <workspace-dir>}"
[ -d "$WS" ] || { echo "test-runner: no workspace dir '$WS'" >&2; exit 2; }
cd "$WS"
mkdir -p .tests

command -v jq >/dev/null 2>&1 || { echo "test-runner: jq required" >&2; exit 2; }

# ---- sandbox: privilege-drop for untrusted, model-generated code --------------------------
# Every test/install command below is written by the code-gen agent (an LLM) and EXECUTED here.
# When HERMES_SANDBOX_USER is set, each runs as that unprivileged user, so a malicious or
# prompt-injected payload can't read the invoker's vault / ~/.hermes keys / SSH. Fail-closed:
# if the drop can't work, abort rather than run untrusted code as the invoking user.
#   Scope (honest): this isolates the FILESYSTEM. macOS has no per-process network namespace,
#   so a payload still can't read your secrets but could still make outbound network calls.
SANDBOX_USER="${HERMES_SANDBOX_USER:-}"
SANDBOX_PREFIX=()
if [ -n "$SANDBOX_USER" ]; then
  if ! sudo -n -u "$SANDBOX_USER" true 2>/dev/null; then
    echo "test-runner: HERMES_SANDBOX_USER='$SANDBOX_USER' set but 'sudo -n -u $SANDBOX_USER true' failed — refusing to run untrusted code unsandboxed. Configure the account + /etc/sudoers.d, or unset HERMES_SANDBOX_USER." >&2
    exit 2
  fi
  # HOME/PATH set explicitly (sudo resets env); umask 0000 inside the drop (see sandboxed())
  # keeps sandbox-user-created files (node_modules, caches) deletable by the invoker on cleanup.
  SANDBOX_PREFIX=(sudo -n -u "$SANDBOX_USER" /usr/bin/env "HOME=$WS" "PATH=$PATH")
  echo "    · sandbox: project code runs as '$SANDBOX_USER'" >&2
else
  echo "test-runner: ⚠ executing model-generated code WITHOUT a sandbox — set HERMES_SANDBOX_USER (e.g. _hermestest) to isolate it from your vault/keys." >&2
fi

# sandboxed <cmd-string> — run a command string through the privilege drop, or directly when
# sandboxing is off. Output redirection stays in the caller's shell, so logs are owner-written.
sandboxed() {
  if [ "${#SANDBOX_PREFIX[@]}" -gt 0 ]; then
    "${SANDBOX_PREFIX[@]}" bash -c "umask 0000; $1"
  else
    bash -c "$1"
  fi
}

STACK="unknown"

# ---- detection ---------------------------------------------------------------------------
# detect_stack runs in the MAIN shell (detect_unit runs in a $() subshell, so a STACK set
# there would be lost) — set the project stack once, up front, from on-disk markers.
detect_stack() {
  if [ -f package.json ]; then STACK="node"
  elif [ -f composer.json ]; then STACK="php"
  elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ] || [ -d tests ] || ls test_*.py >/dev/null 2>&1; then STACK="python"
  elif [ -f Makefile ] && grep -qE '^test:' Makefile; then STACK="make"
  else STACK="unknown"; fi
}

detect_unit() {
  [ -n "${UNIT_CMD+x}" ] && { printf '%s' "$UNIT_CMD"; return; }
  if [ -f package.json ]; then
    local t; t="$(jq -r '.scripts.test // empty' package.json 2>/dev/null)"
    if [ -n "$t" ] && ! printf '%s' "$t" | grep -q 'no test specified'; then printf 'npm test --silent'; return; fi
    if jq -e '.devDependencies.vitest // .dependencies.vitest' package.json >/dev/null 2>&1; then printf 'npx vitest run'; return; fi
    if jq -e '.devDependencies.jest // .dependencies.jest' package.json >/dev/null 2>&1; then printf 'npx jest'; return; fi
    printf ''; return
  fi
  if [ -f composer.json ]; then
    if [ -x vendor/bin/phpunit ]; then printf 'vendor/bin/phpunit'; return; fi
    if [ -f artisan ]; then printf 'php artisan test'; return; fi
    if jq -e '.scripts.test' composer.json >/dev/null 2>&1; then printf 'composer test'; return; fi
    printf ''; return
  fi
  if [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ] || [ -d tests ] || ls test_*.py >/dev/null 2>&1; then
    if python3 -c 'import pytest' >/dev/null 2>&1; then printf 'python3 -m pytest -q'; return; fi
    printf 'python3 -m unittest discover -p test_*.py'; return
  fi
  if [ -f Makefile ] && grep -qE '^test:' Makefile; then printf 'make test'; return; fi
  printf ''
}
detect_integration() {
  [ -n "${INTEGRATION_CMD+x}" ] && { printf '%s' "$INTEGRATION_CMD"; return; }
  case "$STACK" in
    node) jq -e '.scripts["test:integration"]' package.json >/dev/null 2>&1 && printf 'npm run test:integration'; ;;
    php)  if [ -f artisan ]; then printf 'php artisan test --group integration';
          elif [ -x vendor/bin/phpunit ]; then printf 'vendor/bin/phpunit --group integration'; fi ;;
    python) python3 -c 'import pytest' >/dev/null 2>&1 && printf 'python3 -m pytest -q -m integration'; ;;
  esac
}
detect_playwright() {
  [ -n "${PLAYWRIGHT_CMD+x}" ] && { printf '%s' "$PLAYWRIGHT_CMD"; return; }
  if ls playwright.config.* >/dev/null 2>&1; then printf 'npx playwright test --reporter=line'; fi
}

# ---- counts (best-effort; exit code is authoritative for pass/fail) -----------------------
parse_passed() { grep -oE '([0-9]+) (passed|tests?,? OK|Ran [0-9]+)' "$1" 2>/dev/null | grep -oE '[0-9]+' | head -1; }
parse_failed() {
  local f; f="$(grep -oiE '([0-9]+) (failed|failures?|errors?)' "$1" 2>/dev/null | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null)"
  printf '%s' "${f:-0}"
}

# ---- install (best-effort, opt-in) -------------------------------------------------------
maybe_install() {
  [ "${TEST_RUNNER_INSTALL:-0}" = 1 ] || return 0
  # Install runs untrusted lifecycle scripts too (npm postinstall, etc.) — route it through the
  # same privilege drop as the test layers.
  case "$STACK" in
    node) [ -d node_modules ] || sandboxed 'npm install --no-audit --no-fund' >.tests/install.log 2>&1 || true ;;
    php)  [ -d vendor ] || sandboxed 'composer install -q' >.tests/install.log 2>&1 || true ;;
    python) sandboxed 'python3 -m pip install -e .' >.tests/install.log 2>&1 || sandboxed 'python3 -m pip install -r requirements.txt' >.tests/install.log 2>&1 || true ;;
  esac
}

# ---- run one layer; echo its JSON result object ------------------------------------------
# run_layer <name> <gate: run|skip> <cmd> — empty cmd ⇒ absent; gate=skip ⇒ skipped.
run_layer() {
  local name="$1" gate="$2" cmd="$3"
  local log=".tests/$name.log" status passed failed excerpt present=true ec
  if [ -z "$cmd" ]; then
    jq -n --arg s absent '{present:false,status:$s,passed:0,failed:0,cmd:"",excerpt:""}'; return
  fi
  if [ "$gate" = skip ]; then
    jq -n --arg s skipped --arg c "$cmd" '{present:false,status:$s,passed:0,failed:0,cmd:$c,excerpt:"prior layer not green"}'; return
  fi
  echo "    · $name: $cmd" >&2
  sandboxed "$cmd" >"$log" 2>&1; ec=$?
  passed="$(parse_passed "$log")"; failed="$(parse_failed "$log")"
  case "$ec" in
    0)   status=pass ;;
    5)   status=absent; present=false ;;   # pytest convention: no tests collected ⇒ no such layer
    127) status=error ;;
    *)   status=fail ;;
  esac
  excerpt="$(tail -c 4000 "$log")"
  jq -n --argjson pr "$present" --arg s "$status" --argjson p "${passed:-0}" --argjson f "${failed:-0}" \
        --arg c "$cmd" --arg e "$excerpt" \
    '{present:$pr,status:$s,passed:$p,failed:$f,cmd:$c,excerpt:$e}'
}

detect_stack
# Python imports: put the workspace root and a `src/` dir on PYTHONPATH so both flat layouts
# (module beside tests) and src-layouts (src/<pkg>/) import without needing an editable install.
[ "$STACK" = python ] && export PYTHONPATH="src:.${PYTHONPATH:+:$PYTHONPATH}"
UNIT_C="$(detect_unit)"

# Hybrid fallback (opt-in): if the deterministic detectors find no unit command and
# TEST_RUNNER_DISCOVER=1, ask the shell-enabled test-runner AGENT to discover the commands
# for an odd/non-standard project, then run THOSE deterministically (the agent finds the
# command; this script still owns the authoritative exit code).
if [ -z "$UNIT_C" ] && [ "${TEST_RUNNER_DISCOVER:-0}" = 1 ] && [ -x "$REPO_ROOT/agents/test-runner/run.sh" ]; then
  echo "    · no command detected — consulting test-runner agent (discovery)" >&2
  disco="$( "$REPO_ROOT/agents/test-runner/run.sh" "Discover the test commands for the project in this directory: $WS" 2>>.tests/discover.log | tail -1 )"
  if printf '%s' "$disco" | jq -e . >/dev/null 2>&1; then
    export UNIT_CMD="$(printf '%s' "$disco" | jq -r '.unit_cmd // ""')"
    export INTEGRATION_CMD="$(printf '%s' "$disco" | jq -r '.integration_cmd // ""')"
    export PLAYWRIGHT_CMD="$(printf '%s' "$disco" | jq -r '.playwright_cmd // ""')"
    UNIT_C="$(detect_unit)"
  fi
fi
INT_C="$(detect_integration)"; PW_C="$(detect_playwright)"
maybe_install
st() { printf '%s' "$1" | jq -r .status; }

# Layers run IN ORDER, each gated on the previous being green (pass, or absent for the
# optional layers). unit must actually pass; integration/playwright that don't exist (absent)
# don't block. A failed/errored layer stops the chain and fails the whole run.
UNIT_R="$(run_layer unit run "$UNIT_C")";          us="$(st "$UNIT_R")"
[ "$us" = pass ] && gi=run || gi=skip
INT_R="$(run_layer integration "$gi" "$INT_C")";   is="$(st "$INT_R")"
if [ "$us" = pass ] && { [ "$is" = pass ] || [ "$is" = absent ]; }; then gp=run; else gp=skip; fi
PW_R="$(run_layer playwright "$gp" "$PW_C")";        ps="$(st "$PW_R")"

OK=false
if [ "$us" = pass ] && { [ "$is" = pass ] || [ "$is" = absent ]; } && { [ "$ps" = pass ] || [ "$ps" = absent ]; }; then
  OK=true
fi

jq -n --arg stack "$STACK" --argjson ok "$OK" \
      --argjson unit "$UNIT_R" --argjson integration "$INT_R" --argjson playwright "$PW_R" \
  '{ok:$ok, stack:$stack, layers:{unit:$unit, integration:$integration, playwright:$playwright}}'
