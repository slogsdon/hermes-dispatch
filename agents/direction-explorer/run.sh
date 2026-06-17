#!/usr/bin/env bash
# direction-explorer — brief → framed problem + ranked directions + a pick (workflow Step 2).
#   ./feature-brief/run.sh "idea" | ./direction-explorer/run.sh
#   echo "brief…" | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
