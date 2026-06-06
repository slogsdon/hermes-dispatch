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
