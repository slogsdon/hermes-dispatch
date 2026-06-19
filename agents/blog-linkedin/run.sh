#!/usr/bin/env bash
# blog-linkedin — pipe the design brief in, get a complete HTML artifact out.
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
