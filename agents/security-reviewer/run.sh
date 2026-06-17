#!/usr/bin/env bash
# security-reviewer — review a diff for vulnerabilities (workflow Step 5, hardening).
#   git diff main... | ./run.sh
#   gh pr diff 123   | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
