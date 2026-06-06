# DIFM: Do It For Me

The container path. `docker compose up` brings up the LiteLLM proxy and the dispatch server, configured entirely from environment variables. Best for a hands-off, reproducible deployment: a homelab box, a VPS, an always-on Mini.

## Prerequisites

- Docker plus Docker Compose.
- A model backend reachable from the containers:
  - Cloud (simplest in containers): set provider API keys in `.env`.
  - Local Ollama: run Ollama on the host. The compose file reaches it at `host.docker.internal:11434`.

## Run it

```bash
cd docker
cp .env.example .env        # then edit: set your keys and model map
docker compose up -d
docker compose logs -f dispatch
```

The dispatch server is then on `http://localhost:7777`, and reachable over Tailscale if you run Tailscale on the host. See [tailscale-mobile.md](tailscale-mobile.md).

## What comes up

| Service | Role | Port |
|---------|------|------|
| `litellm` | the proxy gateway: serves the 8 aliases, routes to your backend | `4000` |
| `dispatch` | the mobile dispatch server plus UI (stdlib Python) | `7777` |

`bootstrap.sh` runs on first start. It reads the env vars and generates the LiteLLM model map (alias to model), so you configure everything in one `.env` instead of hand-writing a LiteLLM config.

## Configuration: .env

Everything is driven from `docker/.env`. See `docker/.env.example` for the full list. The essentials:

```bash
# Master key the dispatch server uses to talk to LiteLLM
LITELLM_MASTER_KEY=sk-local-change-me

# Pick ONE backend posture.
# (a) Cloud: set the providers you use:
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
# (b) Local Ollama on the host:
OLLAMA_BASE=http://host.docker.internal:11434

# Per-alias model strings (defaults target cloud; override per alias)
MODEL_CLASSIFY=openai/gpt-4o-mini
MODEL_QUALITY=anthropic/claude-3-5-sonnet-latest
# one per alias: classify, chat, review, code, analyze, pipeline, write, quality
```

## Notes and limits

- Agents and pipelines run on the host, not in the container. The compose stack serves the dispatch layer (router, enhancer, UI) and the LiteLLM gateway. It does not containerize the per-agent shell wrappers, which need Hermes and your shell. Run those with `./agents/<name>/run.sh` on the host, pointed at the containerized LiteLLM on `:4000`. This keeps the image small and stdlib only.
- Local models need Ollama on the host, or a separate Ollama container with the models pulled. The proxy reaches it via `host.docker.internal`.
- The dispatch image installs nothing beyond Python stdlib. `requirements.txt` is empty by design.

Prefer to wire it yourself? See [diy.md](diy.md). Prefer a guided local setup? See [diwm.md](diwm.md).
