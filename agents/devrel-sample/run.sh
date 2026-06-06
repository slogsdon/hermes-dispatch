#!/usr/bin/env bash
# devrel-sample, generate a developer-advocacy code sample.
#   ./run.sh "Show a TypeScript example of capturing a payment with the Foo SDK"
#   cat spec.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
