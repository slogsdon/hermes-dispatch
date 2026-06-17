#!/usr/bin/env bash
#
# test_testrunner.sh — tests for the M1.1 sandbox logic in lib/test-runner.sh.
# No real privilege or account needed: the fail-closed path uses a sudo that legitimately
# can't drop, and the happy path uses a FAKE sudo on PATH that records its invocation.
#
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TR="$ROOT/lib/test-runner.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }

command -v jq >/dev/null 2>&1 || { echo "skip: jq required"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkws() {  # a workspace with one passing python unit test
  mkdir -p "$1"
  cat > "$1/test_x.py" <<'PY'
import unittest
class T(unittest.TestCase):
    def test_ok(self):
        self.assertEqual(1, 1)
PY
}

echo "== A: no sandbox → tests run, with a loud warning =="
WSA="$TMP/a"; mkws "$WSA"
outA="$(HERMES_SANDBOX_USER='' "$TR" "$WSA" 2>"$TMP/a.err")"
printf '%s' "$outA" | jq -e '.ok == true' >/dev/null 2>&1 && ok "A ok:true" || bad "A ok:true" "$outA"
grep -q "WITHOUT a sandbox" "$TMP/a.err" && ok "A warns" || bad "A warns" "$(cat "$TMP/a.err")"

echo "== B: sandbox user that can't be sudo'd to → fail-closed (exit 2, no test run) =="
WSB="$TMP/b"; mkws "$WSB"
HERMES_SANDBOX_USER="nope_no_such_user_$$" "$TR" "$WSB" >"$TMP/b.out" 2>"$TMP/b.err"; rcB=$?
[ "$rcB" = 2 ] && ok "B exits 2" || bad "B exits 2" "rc=$rcB"
grep -q "refusing to run untrusted code" "$TMP/b.err" && ok "B refuses" || bad "B refuses" "$(cat "$TMP/b.err")"

echo "== C: fake sudo on PATH → wrapper invoked, tests still pass =="
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/sudo" <<'SUDO'
#!/usr/bin/env bash
# fake sudo: log the call, strip `-n` and `-u USER`, exec the rest as the current user.
echo "INVOKED $*" >> "$FAKE_SUDO_LOG"
args=("$@")
[ "${args[0]:-}" = "-n" ] && args=("${args[@]:1}")
[ "${args[0]:-}" = "-u" ] && args=("${args[@]:2}")
exec "${args[@]}"
SUDO
chmod +x "$BIN/sudo"
WSC="$TMP/c"; mkws "$WSC"; : > "$TMP/sudo.log"
outC="$(FAKE_SUDO_LOG="$TMP/sudo.log" HERMES_SANDBOX_USER=fakeuser PATH="$BIN:$PATH" "$TR" "$WSC" 2>"$TMP/c.err")"
printf '%s' "$outC" | jq -e '.ok == true' >/dev/null 2>&1 && ok "C ok:true" || bad "C ok:true" "$outC / $(cat "$TMP/c.err")"
[ -s "$TMP/sudo.log" ] && ok "C invoked the sudo wrapper" || bad "C invoked the sudo wrapper" "log empty"
grep -q "fakeuser" "$TMP/sudo.log" && ok "C dropped to sandbox user" || bad "C dropped to sandbox user" "$(cat "$TMP/sudo.log")"

echo ""
printf 'test-runner sandbox: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
