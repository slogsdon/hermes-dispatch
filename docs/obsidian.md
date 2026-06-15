# Obsidian integration (optional)

The dispatch server can save an agent's output straight into an [Obsidian](https://obsidian.md) vault as a Markdown note. It's useful from the phone ("save that to my vault"). It's disabled by default and entirely optional. Nothing else in the project depends on it.

## Enable it

Set `OBSIDIAN_VAULT` to your vault's absolute path, or fill in `obsidian_vault:` in `config.yaml` and let `setup.sh` wire it:

```bash
export OBSIDIAN_VAULT="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personal"
python3 dispatch/server.py
# startup prints:  obsidian: enabled at /Users/you/.../Personal
```

Leave `OBSIDIAN_VAULT` blank and the feature is fully off: no intent matching, no `/obsidian-save` action, no vault writes.

| Var | Default | Meaning |
|-----|---------|---------|
| `OBSIDIAN_VAULT` | empty (disabled) | absolute path to your vault |
| `OBSIDIAN_BIN` | auto (`which obsidian`) | path to the optional `obsidian` CLI |

## How saving works

When enabled, the server does three things:

1. Picks a title from the artifact's first real heading, falling back to a generated name, sanitized for the filesystem.
2. Tries the `obsidian` CLI first if present, then verifies the file landed. If it didn't, it writes the Markdown into the vault directly. This makes the action reliable even headless, for example from a launchd daemon that can't reach the GUI app's IPC.
3. Commits the new note to the vault's git repo with a `docs: <title>` message. This is best-effort and scoped to just the new file.

Two ways to trigger it from the chat:

- Intent: a message like "save that to my vault" or "log this note" saves the most recent artifact in the session.
- Explicit: `POST /obsidian-save` with `{path|content, agent}`.

## macOS and iCloud caveat

If you run the server under launchd and your vault lives in iCloud, the daemon may lack Full Disk Access, which can make the git commit hang or fail. The save itself still succeeds (the note is written); only the commit is deferred. Grant the launchd process Full Disk Access in System Settings, Privacy & Security, to fix it.

## Not an Obsidian user?

Ignore this entirely. Every agent's output is plain Markdown on stdout, so pipe it wherever you like:

```bash
./agents/vault-distiller/run.sh < note.md > distilled.md
```

## Memory feeders (CLI / pipeline)

The server save above is the phone-facing path. For terminal and scripted use there are two
companion feeders under `lib/`. Agents run a closed toolset and can't call the `obsidian` CLI
themselves, so these do the vault I/O *around* an agent — read context in before it runs, write
its output back after. Both require the optional `obsidian` CLI (`OBSIDIAN_BIN`, see above) and a
running Obsidian; both **always exit 0** and degrade to a no-op when it's missing, so they never
break a run. Both honor `HERMES_DRY_RUN=1`.

**Read — `lib/obsidian-context.sh`** searches your vault and emits a `## Memory Context` block so
an agent grounds its work in prior notes instead of starting cold:

```bash
echo "<task input>" | lib/obsidian-context.sh | ./agents/prospect-researcher/run.sh
lib/obsidian-context.sh 'payments fintech ICP'                       # explicit query
OBSIDIAN_CONTEXT_PATH='Context/Memory' lib/obsidian-context.sh '…'   # scope a folder
```

Env: `OBSIDIAN_QUERY`, `OBSIDIAN_CONTEXT_LIMIT` (default 5), `OBSIDIAN_CONTEXT_PATH` (folder
scope), `OBSIDIAN_VAULT_NAME` (CLI vault selector; blank = active vault).

**Write — `lib/obsidian-save.sh`** appends an agent's output to a vault note and commits it. It's
**transparent** (stdout = stdin) so it can sit at the end of any pipe:

```bash
./agents/decision-journal/run.sh < input.md | lib/obsidian-save.sh 'Decision Log'
OBSIDIAN_SAVE_DAILY=1 lib/obsidian-save.sh < out.md     # append to today's daily note
```

Env: `OBSIDIAN_SAVE_DAILY=1` / a note-name arg / `OBSIDIAN_SAVE_FILE` (target), `OBSIDIAN_VAULT`
(filesystem path — the scoped git commit runs here; blank skips only the commit),
`OBSIDIAN_VAULT_NAME`, `OBSIDIAN_SAVE_HEADING`, `OBSIDIAN_SAVE_LABEL`, `OBSIDIAN_NO_COMMIT=1`.

> Wiring these as automatic `tool` steps inside a `pipelines/*.json` run needs the pipeline
> executor to support non-agent steps, which this repo's `lib/orchestrate.sh` does not yet. For
> now use them as the standalone pipe stages shown above.
