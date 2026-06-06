#!/usr/bin/env bash
# gtm-planner, turn a product/feature brief into a structured GTM plan.
#   ./run.sh "Brief: a local-LLM agent toolkit for indie devs. Free, runs on a Mac Mini..."
#   cat feature-brief.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
