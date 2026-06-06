#!/usr/bin/env bash
# retro-generator, synthesize raw project notes into a structured retrospective.
#   cat project-notes.md | ./run.sh > retro.md
#   ./run.sh "Project: client site. Shipped 2 weeks late. Logo assets arrived late..."
#
# Output is Obsidian-ready Markdown, pipe it to a file, or hand it to the obsidian skill
# to create the note (this agent never touches the vault directly, by design).
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
