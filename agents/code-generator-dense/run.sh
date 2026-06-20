#!/usr/bin/env bash
# code-generator-dense — last-resort heavy builder (alias: dense). Same role as
# code-generator; invoked by the validate test-loop's escalation hook when the fast
# builder exhausts its cycles. REFINE mode: pipe code + test failures back in.
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
