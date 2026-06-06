#!/usr/bin/env bash
# proposal-writer, scope brief → a structured, client-ready proposal.
#   ./run.sh "Problem: ... Deliverables: ... Timeline: 6 weeks. Budget: ~\$18k."
#   cat scope-brief.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
