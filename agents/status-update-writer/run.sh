#!/usr/bin/env bash
# status-update-writer, turn done/blocked/next bullets into a client status update.
#   ./run.sh "DONE: shipped auth. BLOCKED: waiting on client logo. NEXT: dashboard."
#   cat notes.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
