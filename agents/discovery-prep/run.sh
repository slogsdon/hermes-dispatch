#!/usr/bin/env bash
# discovery-prep, prospect + meeting goal → background, 5 ordered questions, and intent.
#   ./run.sh "Prospect: Acme Payments. Goal: scope a developer-docs revamp."
#   cat prospect-brief.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
