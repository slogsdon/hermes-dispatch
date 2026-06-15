#!/usr/bin/env bash
#
# obsidian-save.sh — vault MEMORY WRITE feeder: persist an agent's output to your Obsidian vault.
#
# The write-side companion to obsidian-context.sh. Because Hermes agents have no shell, they
# can't append to the vault themselves — so saving an output (a decision, a brief, a dossier, a
# retro) is a deterministic `tool` step that appends the upstream text to a vault note and
# commits. It is TRANSPARENT: stdin passes through to stdout unchanged, so it can sit anywhere in
# a pipeline (or at the end) without altering the data the next step receives.
#
# Usage:
#   echo "<agent output>" | lib/obsidian-save.sh 'Decision Log'      # append to a named note
#   OBSIDIAN_SAVE_FILE='Decision Log' lib/obsidian-save.sh < output.md
#   OBSIDIAN_SAVE_DAILY=1 lib/obsidian-save.sh < output.md           # append to today's daily note
#
#   # In a pipeline, drop it after the agent whose output you want kept; it writes the same key
#   # it reads, so downstream steps are unaffected:
#   #   { "id":"save", "type":"tool", "cmd":"lib/obsidian-save.sh",
#   #     "reads":"decision", "writes":"decision", "format":"md" }
#
# Target resolution (first that applies):
#   1. OBSIDIAN_SAVE_DAILY=1            → today's daily note (resolved via `obsidian daily:read`)
#   2. arg / OBSIDIAN_SAVE_FILE=<name>  → that note (created if missing)
#   3. (neither)                        → no-op passthrough (nothing saved)
#
# Tunables (env):
#   OBSIDIAN_SAVE_HEADING   markdown heading prefixed before the entry (default '### <agent> — <ts>')
#   OBSIDIAN_SAVE_LABEL     label used in the default heading (default 'Hermes agent')
#   OBSIDIAN_VAULT          vault filesystem path (same var dispatch/server.py uses); the scoped
#                           git commit runs here. Blank → write only, commit skipped.
#   OBSIDIAN_VAULT_NAME     vault NAME for the obsidian CLI (else its default/active vault)
#   OBSIDIAN_NO_COMMIT=1    skip the post-write vault git commit
#
# Always exits 0 and always re-emits stdin. If `obsidian` is missing / Obsidian is closed / no
# target is configured, it just passes stdin through (logging the skip to stderr) — it never
# breaks a run and never loses the data. Honors HERMES_DRY_RUN=1 (passthrough only, no write).
#
set -euo pipefail

# Vault filesystem path for the scoped git commit — same OBSIDIAN_VAULT the dispatch server uses.
# Blank disables only the commit (the note is still written); never hardcode a personal path.
VAULT_PATH="${OBSIDIAN_VAULT:+$(eval echo "$OBSIDIAN_VAULT")}"
VAULT_ARG=(); [[ -n "${OBSIDIAN_VAULT_NAME:-}" ]] && VAULT_ARG=(vault="$OBSIDIAN_VAULT_NAME")
LABEL="${OBSIDIAN_SAVE_LABEL:-Hermes agent}"

CONTENT=""; [[ ! -t 0 ]] && CONTENT="$(cat)"
# Transparent passthrough: whatever happens below, the next step gets the original output.
passthrough() { printf '%s' "$CONTENT"; }
trap passthrough EXIT

[[ -n "$CONTENT" ]] || { echo "obsidian-save: empty input — nothing to save." >&2; exit 0; }

if [[ "${HERMES_DRY_RUN:-}" == "1" ]]; then
  echo "obsidian-save: dry-run — would append $(printf '%s' "$CONTENT" | wc -l | tr -d ' ') lines to the vault." >&2
  exit 0
fi

if ! command -v obsidian >/dev/null 2>&1; then
  echo "obsidian-save: 'obsidian' CLI not found on PATH — passthrough only, nothing saved." >&2
  exit 0
fi

# Resolve the target note.
TARGET=""
if [[ "${OBSIDIAN_SAVE_DAILY:-}" == "1" ]]; then
  # daily:read prints the note's name/path; first non-empty token is the note name we append by.
  DAILY="$(obsidian ${VAULT_ARG[@]+"${VAULT_ARG[@]}"} daily:read 2>/dev/null | grep -m1 -E '[[:alnum:]]' || true)"
  TARGET="$(printf '%s' "$DAILY" | sed -E 's#\.md$##; s#^.*/##; s/[[:space:]]+$//')"
  [[ -n "$TARGET" ]] || { echo "obsidian-save: could not resolve today's daily note (is Obsidian running?) — passthrough only." >&2; exit 0; }
elif [[ $# -gt 0 && -n "$1" ]]; then
  TARGET="$1"
elif [[ -n "${OBSIDIAN_SAVE_FILE:-}" ]]; then
  TARGET="$OBSIDIAN_SAVE_FILE"
else
  echo "obsidian-save: no target note (set OBSIDIAN_SAVE_DAILY=1, pass a note name, or set OBSIDIAN_SAVE_FILE) — passthrough only." >&2
  exit 0
fi

TS="$(date '+%Y-%m-%d %H:%M')"
HEADING="${OBSIDIAN_SAVE_HEADING:-### $LABEL — $TS}"
ENTRY="$(printf '%s\n\n%s' "$HEADING" "$CONTENT")"

# The obsidian CLI exits 0 even when a note is MISSING (the error goes to stdout), so we can't
# trust exit codes — every check below inspects the command's OUTPUT string instead.
ob() { obsidian ${VAULT_ARG[@]+"${VAULT_ARG[@]}"} "$@" 2>&1; }

# Ensure the note exists. Daily notes always exist; for a named target, create it if `read`
# reports it's missing. We must create-then-append (not rely on append) because append to a
# nonexistent note no-ops — and a bare append by a name that doesn't resolve can fall back to
# whatever note is active in Obsidian (a known CLI footgun), which the match-guard below catches.
if [[ "${OBSIDIAN_SAVE_DAILY:-}" != "1" ]]; then
  if ob read file="$TARGET" | grep -qiE 'not found|^Error:'; then
    if ! ob create name="$TARGET" content="# $TARGET" silent | grep -qi 'Created'; then
      echo "obsidian-save: could not create note '$TARGET' (is Obsidian running?) — passthrough only, nothing saved." >&2
      exit 0
    fi
  fi
fi

APPEND_OUT="$(ob append file="$TARGET" content="$ENTRY")"
if ! printf '%s' "$APPEND_OUT" | grep -qi 'Appended to:'; then
  echo "obsidian-save: append to '$TARGET' failed (${APPEND_OUT:-no response}; is Obsidian running?) — passthrough only, nothing saved." >&2
  exit 0
fi
# Footgun guard: the appended file named back to us must be our target. If it isn't, the CLI fell
# back to the active note — abort the commit rather than persist to (and commit) the wrong file.
if ! printf '%s' "$APPEND_OUT" | grep -qF "$TARGET"; then
  echo "obsidian-save: WARNING — append landed on a different note than '$TARGET' ($APPEND_OUT); not saving/committing." >&2
  exit 0
fi
echo "obsidian-save: appended ${LABEL} output to vault note '$TARGET'." >&2

if [[ "${OBSIDIAN_NO_COMMIT:-}" != "1" && -d "$VAULT_PATH/.git" ]]; then
  # Commit ONLY the saved note, never the whole vault working tree (`git add -A` would sweep
  # unrelated in-flight edits — and a synced iCloud vault often has them — into this commit).
  # Derive the note's vault-relative path from the CLI's "Appended to:" line; fall back to
  # <TARGET>.md at the vault root (the convention the mobile server also assumes).
  REL="$(printf '%s' "$APPEND_OUT" | sed -nE 's#.*Appended to:[[:space:]]*##p' | head -1)"
  REL="${REL#"$VAULT_PATH"/}"
  [[ -n "$REL" && -f "$VAULT_PATH/$REL" ]] || REL="${TARGET}.md"
  if [[ -f "$VAULT_PATH/$REL" ]]; then
    git -C "$VAULT_PATH" add -- "$REL" >/dev/null 2>&1 \
      && git -C "$VAULT_PATH" commit -m "docs: append ${LABEL} output to ${TARGET}" -- "$REL" >/dev/null 2>&1 \
      || true
  else
    echo "obsidian-save: could not resolve saved note path for a scoped commit; skipping commit (note was still written)." >&2
  fi
fi
