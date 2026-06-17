#!/usr/bin/env bash
# release-prep — change summary → pre-launch checklist + rollback + go/no-go (workflow Step 6).
#   ./run.sh "$(git log --oneline main..HEAD)"
#   echo "what's shipping…" | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
