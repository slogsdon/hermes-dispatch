#!/usr/bin/env bash
# tos-reviewer, fast risk pass on terms of service / a vendor agreement before accepting.
#   pbpaste | ./run.sh
#   ./run.sh "$(cat vendor-terms.txt)"
#   curl -s https://example.com/terms.txt | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
