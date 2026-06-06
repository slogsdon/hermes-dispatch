#!/usr/bin/env bash
# contract-reviewer, fast risk pass over a contract / vendor agreement.
#   cat agreement.txt | ./run.sh
#   ./run.sh "$(pbpaste)"
#   pdftotext msa.pdf - | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
