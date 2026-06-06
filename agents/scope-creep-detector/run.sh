#!/usr/bin/env bash
# scope-creep-detector, classify a new client request against the agreed scope.
#   ./run.sh "AGREED SCOPE: <paste>. NEW REQUEST: <paste>."
#   cat scope-and-request.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
