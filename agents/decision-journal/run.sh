#!/usr/bin/env bash
# decision-journal, capture a decision + reasoning as an Obsidian note for future-Shane.
#   ./run.sh "Today is $(date +%F). Decision: take the contract role or stay solo. \
#   Options: ... Stakes: ..." > "Decisions/$(date +%F) contract-vs-solo.md"
#   cat decision-brief.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
