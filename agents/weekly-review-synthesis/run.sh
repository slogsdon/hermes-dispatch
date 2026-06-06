#!/usr/bin/env bash
# weekly-review-synthesis, synthesize the week's notes into an Obsidian weekly review.
#   cat ~/vault/Daily/2026-06-0*.md | ./run.sh > "Weekly/2026-W23.md"
#   ./run.sh "$(pbpaste)"
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
