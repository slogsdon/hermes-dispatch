#!/usr/bin/env bash
# swarm-worker — execute one small code task; terse code out. Fanned out by bin/swarm.py.
#   ./run.sh "Add JSDoc to this function" "function foo(x){ return x * 2; }"
#   printf '%s\n\n%s' "$instruction" "$code" | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
