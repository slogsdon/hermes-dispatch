#!/usr/bin/env bash
# impl-planner — chosen direction → ordered, testable implementation plan (workflow Step 3).
#   ./direction-explorer/run.sh < brief | ./impl-planner/run.sh
#   echo "direction…" | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
