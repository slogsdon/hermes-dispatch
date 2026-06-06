#!/usr/bin/env bash
# meeting-to-actions, extract decisions/actions/questions/follow-ups as Obsidian Markdown.
#   cat meeting-notes.md | ./run.sh
#   ./run.sh "$(pbpaste)" > "Meetings/$(date +%F) standup.md"
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
