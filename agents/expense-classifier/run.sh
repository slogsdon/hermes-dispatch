#!/usr/bin/env bash
# expense-classifier, append a tax `category` column to transaction rows (CSV in, CSV out).
#   cat transactions.csv | ./run.sh > classified.csv
#   ./run.sh "$(pbpaste)"
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
