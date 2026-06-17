#!/usr/bin/env bash
# code-generator — implementation plan → actual runnable code (workflow Step 4, Build).
#   ./impl-planner/run.sh < direction | ./code-generator/run.sh
#   ./run.sh "$(cat plan.md)"
# REFINE mode: pipe the existing code AND the review findings (concatenated) back in.
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
