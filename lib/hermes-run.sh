#!/usr/bin/env bash
#
# hermes-run.sh, shared minimal-agent runner for Hermes Agent (v0.14.x)
#
# Hermes has no native per-agent manifest: a "minimal agent" is just the harness
# constrained by flags (see the research brief). This runner reads a flat
# agent.yaml + SOUL.md from an agent directory and emits the canonical
# invocation:
#
#   hermes chat -q "<system prompt>\n\n<input>" -m <alias> --provider <p> \
#          -t "<toolsets>" --max-turns <n> [--ignore-rules] [--ignore-user-config] [-Q]
#
# Usage:
#   lib/hermes-run.sh <agent-dir> [input ...]
#   echo "input" | lib/hermes-run.sh <agent-dir>
#
# Input precedence: CLI args  >  piped stdin  >  none (prompt-only).
#
# Env overrides (mirror the agent-turn wrapper convention):
#   AGENT_HERMES_MODEL     override the alias
#   AGENT_HERMES_PROVIDER  override the provider
#   HERMES_DRY_RUN=1       print the composed command instead of running it
#
set -euo pipefail

AGENT_DIR="${1:?usage: hermes-run.sh <agent-dir> [input ...]}"
shift || true

# --- Project HERMES_HOME -----------------------------------------------------
# Agents run against the repo's own Hermes home (hermes-home/config.yaml) instead
# of ~/.hermes. This drift-proofs the project (it carries its own provider +
# reconciled aliases) and lets config do what flags can't, notably
# display.show_reasoning:false (no "┌─ Reasoning" block) and tirith off.
#
# The committed config is synced into a RUNTIME home outside the repo so Hermes'
# state (sessions, state.db, caches, logs) never pollutes git. Secrets are NEVER
# committed, the LiteLLM key + auth are carried from the user's real ~/.hermes
# at run time. Override the runtime location with HERMES_AGENTS_HOME.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$LIB_DIR")"
PROJECT_HOME_SRC="$REPO_ROOT/hermes-home"
if [[ -f "$PROJECT_HOME_SRC/config.yaml" && "${HERMES_AGENTS_NO_HOME:-}" != "1" ]]; then
  RUNTIME_HOME="${HERMES_AGENTS_HOME:-$HOME/.cache/hermes-agents-home}"
  mkdir -p "$RUNTIME_HOME"
  cp -f "$PROJECT_HOME_SRC/config.yaml" "$RUNTIME_HOME/config.yaml"
  [[ -f "$PROJECT_HOME_SRC/SOUL.md" ]] && cp -f "$PROJECT_HOME_SRC/SOUL.md" "$RUNTIME_HOME/SOUL.md"
  # Carry secrets/auth from the real home (gitignored runtime dir, never the repo)
  [[ -f "$HOME/.hermes/.env" ]]      && cp -f "$HOME/.hermes/.env"      "$RUNTIME_HOME/.env"
  [[ -f "$HOME/.hermes/auth.json" ]] && cp -f "$HOME/.hermes/auth.json" "$RUNTIME_HOME/auth.json"
  export HERMES_HOME="$RUNTIME_HOME"
fi
# -----------------------------------------------------------------------------

CONFIG="$AGENT_DIR/agent.yaml"
PROMPT_FILE="$AGENT_DIR/SOUL.md"
[[ -f "$CONFIG" ]]      || { echo "hermes-run: missing $CONFIG" >&2; exit 1; }
[[ -f "$PROMPT_FILE" ]] || { echo "hermes-run: missing $PROMPT_FILE" >&2; exit 1; }

# Flat-YAML getter: yget <key> [default]
# Handles `key: value`, inline `# comments`, and surrounding quotes.
yget() {
  local key="$1" def="${2-}" line val
  line="$(grep -E "^${key}:" "$CONFIG" | head -1 || true)"
  if [[ -z "$line" ]]; then printf '%s' "$def"; return; fi
  val="$(printf '%s' "$line" \
    | sed -E "s/^${key}:[[:space:]]*//; s/[[:space:]]+#.*$//; s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/")"
  printf '%s' "$val"
}

ALIAS="$(yget alias)"
PROVIDER="$(yget provider litellm)"
MAX_TURNS="$(yget max_turns 1)"
TOOLSETS="$(yget toolsets)"                 # default "" → no tools (minimal)
IGNORE_RULES="$(yget ignore_rules true)"
IGNORE_USER_CONFIG="$(yget ignore_user_config false)"
QUIET="$(yget quiet true)"
PARSE_LAST_LINE="$(yget parse_last_line false)"
STRIP_THINK="$(yget strip_think false)"
STRIP_REASONING="$(yget strip_reasoning false)"
ANSWER_ANCHOR="$(yget answer_anchor)"

# Env overrides
ALIAS="${AGENT_HERMES_MODEL:-$ALIAS}"
PROVIDER="${AGENT_HERMES_PROVIDER:-$PROVIDER}"
[[ -n "$ALIAS" ]] || { echo "hermes-run: agent.yaml 'alias' is required" >&2; exit 1; }

# Gather input
INPUT=""
if [[ $# -gt 0 ]]; then
  INPUT="$*"
elif [[ ! -t 0 ]]; then
  INPUT="$(cat)"
fi

SYSTEM="$(cat "$PROMPT_FILE")"
# No no-tools directive needed: the project home (hermes-home/config.yaml) disables ALL
# toolsets, so Hermes sends zero tool definitions. Nothing for the model to grab, and no
# directive text added to the prompt (which would itself cost context).
if [[ -n "$INPUT" ]]; then
  FULL_PROMPT="${SYSTEM}"$'\n\n===== INPUT =====\n'"${INPUT}"
else
  FULL_PROMPT="$SYSTEM"
fi

# Build args. -t is ALWAYS emitted (empty string = no tools), per the brief's
# minimal template, never inherit the box's 14 default toolsets.
ARGS=(chat -q "$FULL_PROMPT" -m "$ALIAS" --provider "$PROVIDER" \
      -t "$TOOLSETS" --max-turns "$MAX_TURNS")
[[ "$IGNORE_RULES" == "true" ]]       && ARGS+=(--ignore-rules)
[[ "$IGNORE_USER_CONFIG" == "true" ]] && ARGS+=(--ignore-user-config)
[[ "$QUIET" == "true" ]]              && ARGS+=(-Q)

# Resolve the hermes binary by absolute path rather than trusting the ambient PATH. Under a
# launchd daemon (e.g. the dispatch server) PATH is minimal — /opt/homebrew/bin:/usr/bin:/bin
# :/usr/sbin:/sbin — and excludes ~/.local/bin where the hermes wrapper often lives, so a bare
# `hermes` exits 127 ("command not found") and kills the pipeline at its first agent. Prefer an
# explicit override, then a PATH lookup, then the common install path.
HERMES_BIN="${HERMES_BIN:-$(command -v hermes 2>/dev/null || true)}"
[[ -n "$HERMES_BIN" ]] || HERMES_BIN="$HOME/.local/bin/hermes"
[[ -x "$HERMES_BIN" ]] || { echo "hermes-run: hermes binary not found at '$HERMES_BIN' (set HERMES_BIN)" >&2; exit 127; }

if [[ "${HERMES_DRY_RUN:-}" == "1" ]]; then
  printf '%q' "$HERMES_BIN"; printf ' %q' "${ARGS[@]}"; printf '\n'
  exit 0
fi

# Post-processing, applied in order:
#   strip_think     → remove <think>…</think> spans (models that emit them inline).
#   strip_reasoning → remove Hermes' rendered "┌─ Reasoning" block that reasoning models
#                     (quality/write/classify) prepend to stdout. SAFE: only cuts when BOTH
#                     a Reasoning header is detected AND a line matching answer_anchor
#                     exists; otherwise passes output through untouched (never eats a
#                     valid response). Requires answer_anchor, the literal first line of
#                     the agent's output contract (e.g. "## Positioning").
#   parse_last_line → keep only the last non-empty line (single-line JSON guarantee).
post_think() {
  if [[ "$STRIP_THINK" == "true" ]]; then
    perl -0777 -pe 's{<think>.*?</think>}{}gs; s/\A\s+//'
  else
    cat
  fi
}

post_reasoning() {
  if [[ "$STRIP_REASONING" == "true" && -n "$ANSWER_ANCHOR" ]]; then
    ANSWER_ANCHOR="$ANSWER_ANCHOR" perl -0777 -e '
      local $/; my $s = <STDIN> // ""; $s =~ s/\r//g;
      my $a = $ENV{ANSWER_ANCHOR};
      # Only cut when a Reasoning header ("─ Reasoning") is present AND the anchor
      # appears at the start of some line, then drop everything before the anchor.
      if ($s =~ /\xe2\x94\x80 Reasoning/ && $s =~ /^\Q$a\E/m) {
        $s = substr($s, $-[0]);
      }
      print $s;
    '
  else
    cat
  fi
}

# strip_status: drop Hermes harness status lines that are never content (e.g. the
# "⚠️  Reached maximum iterations (N). Requesting summary..." notice). Always on.
strip_status() { sed '/Reached maximum iterations/d'; }

if [[ "$PARSE_LAST_LINE" == "true" ]]; then
  "$HERMES_BIN" "${ARGS[@]}" | strip_status | post_think | post_reasoning | awk 'NF{last=$0} END{if(last!="")print last}'
else
  "$HERMES_BIN" "${ARGS[@]}" | strip_status | post_think | post_reasoning
fi
