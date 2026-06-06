#!/usr/bin/env bash
# inbox-triage, classify a batch of emails, emit one minified JSON array.
#   pbpaste | ./run.sh | jq .
#   ./run.sh "Subj: Q3 budget sign-off, need your ok by EOD
#   Subj: Weekly newsletter from SomeSaaS
#   Subj: Can you review the contract? (from legal)"
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
