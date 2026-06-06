#!/usr/bin/env bash
# gtm-executor, turn a GTM plan/brief into ready-to-ship launch assets.
#   cat gtm-plan.md | ./run.sh
#   ./run.sh "Plan: <positioning, segments, pillars...>. Produce announcement + 2 emails."
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
