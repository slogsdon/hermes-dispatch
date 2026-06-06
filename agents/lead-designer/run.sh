#!/usr/bin/env bash
# lead-designer, design direction (from a brief) or critique (of a text design spec).
#   cat design/acme/DESIGN.md | ./run.sh
#   ./run.sh "Brief: landing page for a local-LLM toolkit, dev audience, dark, minimal."
#   cat tokens.css | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
