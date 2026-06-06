#!/usr/bin/env bash
# followup-drafter, last-interaction context → a short, natural follow-up email (≤150 words).
#   ./run.sh "Discussed their docs pain. Agreed I'd send a scope. Next: proposal by Friday."
#   cat call-notes.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
