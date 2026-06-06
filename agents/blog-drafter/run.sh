#!/usr/bin/env bash
# blog-drafter, draft a blog section from an outline or notes.
#   ./run.sh "Section: why local LLM routing beats one big model. Cover latency, cost, privacy."
#   cat outline.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
