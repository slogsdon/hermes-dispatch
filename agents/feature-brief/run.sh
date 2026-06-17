#!/usr/bin/env bash
# feature-brief — raw idea → business-context brief (workflow Step 1).
#   ./run.sh "an app that drafts standup updates from git history"
#   echo "idea…" | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
