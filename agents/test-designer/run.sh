#!/usr/bin/env bash
# test-designer — task/behavior → failing tests first (workflow Step 4, TDD red step).
#   ./run.sh "parse an ISO-8601 duration string into seconds; reject malformed input"
#   echo "task + acceptance criteria…" | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
