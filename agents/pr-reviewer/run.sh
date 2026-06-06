#!/usr/bin/env bash
# pr-reviewer, review a diff against a five-axis rubric.
#   git diff main... | ./run.sh
#   git show <sha> | ./run.sh
#   gh pr diff 123 | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
