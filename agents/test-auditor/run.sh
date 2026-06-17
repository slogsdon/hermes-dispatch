#!/usr/bin/env bash
# test-auditor — audit generated tests for wrong expectations before code is written.
#   { printf '===== plan =====\n'; cat plan.md; printf '\n===== tests =====\n'; cat tests.md; } | ./run.sh
# In the dev-workflow pipeline it runs as the `test-audit` step, reading [plan, tests].
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
