#!/usr/bin/env bash
#
# run.sh — run the whole hermes-dispatch test net. Exit 0 iff everything passes.
# Used by humans and CI. No third-party deps: stdlib unittest + bash.
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0

echo "### python unit tests"
python3 -m unittest discover -s "$DIR" -p 'test_*.py' -v || rc=1

echo ""
[ "$rc" -eq 0 ] && echo "ALL TESTS PASSED" || echo "TESTS FAILED"
exit "$rc"
