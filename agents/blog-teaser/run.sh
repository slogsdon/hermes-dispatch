#!/usr/bin/env bash
# blog-teaser — pipe the teaser brief in, get one JSON line {linkedin,twitter,bluesky} out.
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
