#!/usr/bin/env bash
# vault-distiller, distill a long note into atomic concepts + links + tags.
#   cat "long-note.md" | ./run.sh
#   ./run.sh "$(obsidian read file='Some Long Note')"
#
# NOTE: pipe note CONTENT in. This agent never touches the vault directly, per the
# rules, vault reads go through the obsidian skill/CLI; feed that output to this agent.
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
