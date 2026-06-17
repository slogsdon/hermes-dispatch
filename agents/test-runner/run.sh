#!/usr/bin/env bash
# test-runner — shell-enabled agent that DISCOVERS how to run a project's tests.
# Run it with the project as the current directory so its terminal commands operate there:
#   ( cd /path/to/project && /path/to/test-runner/run.sh "discover the test commands" )
# Outputs one JSON line: {"stack","unit_cmd","integration_cmd","playwright_cmd","notes"}.
# The orchestrator re-runs those commands via lib/test-runner.sh for ground-truth pass/fail.
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
