#!/usr/bin/env bash
# blog-describer — pipe an article body in, get a one-line meta description out.
#   cat body.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
