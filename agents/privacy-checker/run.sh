#!/usr/bin/env bash
# privacy-checker, review a privacy policy / DPA: data map + GDPR-CCPA gap list.
#   pbpaste | ./run.sh
#   ./run.sh "$(cat privacy-policy.txt)"
#   curl -s https://example.com/privacy.txt | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
