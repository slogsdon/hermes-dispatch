#!/usr/bin/env bash
# triage-router, classify/route one item, emit minified JSON.
#   ./run.sh "Follow up with the payments team re: webhook retries by Friday"
#   echo "$INBOX_ITEM" | ./run.sh | jq .
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
