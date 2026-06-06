# dispatch/: mobile chat over the agent roster

A two-layer chat server that turns the whole agent roster into one phone-friendly chat box. Stdlib-only Python, no pip installs. It's designed to run locally and be reached from your phone over [Tailscale](../docs/tailscale-mobile.md).

```
You (phone)  ->  dispatcher (router + enhancer)  ->  chosen agent  ->  streamed reply
                 picks an agent + a better prompt    its SOUL.md + pinned model
```

## What it does

1. Layer 1, dispatch. Each message goes to a fast router model (the `pipeline` alias) that picks the best agent, and a capable enhancer model (the `analyze` alias) that rewrites your terse request into a detailed, agent-tuned prompt. It returns `{agent, expanded_prompt, reasoning}`.
2. Layer 2, execution. The expanded prompt runs against the chosen agent's own system prompt (`profiles/<name>/SOUL.md`) and pinned model, streamed back token by token over SSE.

Output stays clean without re-implementing Hermes' post-processing. Local reasoning models route their chain-of-thought to a separate `reasoning_content` field, so the server streams `delta.content` and ignores `reasoning_content`, plus a defensive inline-`<think>` stripper.

## Run it

```bash
# Reads agents from ~/.hermes/profiles. Generate those first:
bin/gen-profiles.sh

# Start the server (binds 0.0.0.0:7777 by default):
python3 dispatch/server.py
# Hermes Dispatch on http://0.0.0.0:7777
```

Open `http://localhost:7777` in a browser, or your Tailscale URL on your phone.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/` | the mobile chat UI (`index.html`) |
| `GET` | `/agents` | `{agents:[{name, model, desc}]}` (scans profiles) |
| `GET` | `/history` | full conversation |
| `POST` | `/chat` | SSE stream: `{type:routing}`, `{type:token}*`, `{type:done}` |
| `POST` | `/obsidian-save` | save the last artifact to your vault (if enabled) |
| `GET` | `/healthz` | `ok` |

## Configuration (environment)

| Var | Default | Meaning |
|-----|---------|---------|
| `HERMES_DISPATCH_HOST` | `0.0.0.0` | bind host |
| `HERMES_DISPATCH_PORT` | `7777` | bind port |
| `HERMES_HOME` | `~/.hermes` | where `profiles/` and `.env` (LiteLLM key) live |
| `LITELLM_BASE` | `http://localhost:4000/v1` | LiteLLM proxy base URL |
| `HERMES_ROUTER_MODEL` | `pipeline` | fast alias that routes and classifies |
| `HERMES_DISPATCHER_MODEL` | `analyze` | capable alias that expands the prompt |
| `HERMES_DISPATCH_HOME` | `~/.hermes-dispatch` | chat history store |
| `OBSIDIAN_VAULT` | empty (disabled) | absolute path to enable save-to-vault |

A note on the stack: this is the stdlib `http.server` implementation. No framework, no dependencies. It's the production server for the project, and `requirements.txt` documents that there are no third-party runtime deps.

See [docs/tailscale-mobile.md](../docs/tailscale-mobile.md) for phone access and [docs/obsidian.md](../docs/obsidian.md) for the optional vault integration.
