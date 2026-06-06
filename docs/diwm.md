# DIWM: Do It With Me

An interactive wizard that walks you through setup and generates `config.yaml` from your answers. Best if you want guidance without giving up visibility. It prints every command it runs and asks before doing anything irreversible.

## Run it

```bash
./setup.sh
```

## What it does, step by step

1. Detects your hardware (Apple Silicon, Intel mac, or Linux) and recommends a matching model preset from `examples/`.
2. Asks which backend you want: Ollama (local), an existing LiteLLM proxy, or cloud APIs.
3. For Ollama, lists the recommended models for your hardware tier and offers to `ollama pull` them. You can decline and pull later.
4. Generates `config.yaml` from your answers (hardware preset plus paths), backing up any existing one.
5. Registers Hermes desktop profiles by running `bin/gen-profiles.sh`. Optional, and it asks first.
6. Asks whether to enable Obsidian save-to-vault. If yes, it prompts for the vault path. Left disabled by default.
7. Asks whether to enable Tailscale phone access. If yes, it prints and offers to run the `tailscale serve` command.
8. Optionally starts the server and hits a representative agent with a tiny prompt to confirm the path is live.
9. Prints a summary: what's configured, the URL to bookmark, and what was skipped or left optional.

## Notes

- The wizard is non-destructive. It backs up an existing `config.yaml` to `config.yaml.bak` before writing, and never pulls models or runs `tailscale serve` without an explicit yes.
- It's a plain bash script with no dependencies beyond what the steps need. `ollama`, `hermes`, and `tailscale` are each optional and only used if you choose them. Read it top to bottom; it's meant to be auditable.
- Re-run it any time to reconfigure. It's idempotent.

## After it finishes

```bash
./agents/<name>/run.sh "your input"   # run an agent
python3 dispatch/server.py            # mobile chat, if you enabled it
```

Prefer full manual control? See [diy.md](diy.md). Prefer containers? See [difm.md](difm.md).
