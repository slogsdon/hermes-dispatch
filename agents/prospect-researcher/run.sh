#!/usr/bin/env bash
# prospect-researcher, company/contact → a sales-call research brief.
#   ./run.sh "Stripe, meeting with a DevRel lead about their API docs program."
#   cat prospect-notes.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
