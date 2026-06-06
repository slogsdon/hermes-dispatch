#!/usr/bin/env bash
# social-media-marketer, topic/draft → platform-tailored social posts.
#   ./run.sh "New post: build a minimal local agent in five hermes flags. Link: ..."
#   cat blog-post.md | ./run.sh
set -euo pipefail
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$AGENT_DIR/../../lib/hermes-run.sh" "$AGENT_DIR" "$@"
