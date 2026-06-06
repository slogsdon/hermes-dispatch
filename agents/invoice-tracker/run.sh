#!/usr/bin/env bash
# invoice-tracker, extract invoice fields, emit minified JSON.
#   cat invoice.txt | ./run.sh | jq .
#   ./run.sh "$(pbpaste)"
#   gh ... # any pipe that yields invoice text
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
