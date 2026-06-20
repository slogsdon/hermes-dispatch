#!/usr/bin/env bash
# blog-tagger — pipe a tag brief (allowed tags + title + body) in, get one line of
# comma-separated tag slugs out.
#   cat brief.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
