#!/usr/bin/env bash
# debug-analyzer — symptom + code → ranked root-cause hypotheses + next probe (workflow Step 4).
#   pytest 2>&1 | ./run.sh
#   ./run.sh "$(cat error.log) --- $(cat suspect.py)"
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
