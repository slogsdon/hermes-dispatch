#!/usr/bin/env bash
# cashflow-summarizer, weekly cash digest from a transaction list.
#   cat transactions.csv | ./run.sh
#   ./run.sh "2026-06-01 Stripe payout +4200; 2026-06-02 AWS -380; ..."
#   pbpaste | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
