#!/usr/bin/env bash
# pr-describer — diff (+ commits) → PR title + body (workflow Step 6).
#   git diff main... | ./run.sh
#   { git log --oneline main..HEAD; echo; git diff main...; } | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
