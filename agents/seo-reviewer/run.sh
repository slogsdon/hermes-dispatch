#!/usr/bin/env bash
# seo-reviewer, audit a page/content for on-page SEO + AEO against a rubric.
#   cat page.md | ./run.sh
#   ./run.sh "Target keyword: local LLM routing. Title: ... Meta: ... Body: ..."
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
