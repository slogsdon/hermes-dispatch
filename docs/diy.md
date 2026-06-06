# DIY: Do It Yourself

Full manual control. Wire each piece yourself; nothing is hidden. Best if you already run Hermes plus a model backend and want to understand every moving part.

## Dependencies

- Hermes Agent v0.15+ on `PATH` (`hermes --version`).
- A backend: Ollama (`ollama serve`) or a LiteLLM proxy on `:4000`.
- `jq` for pipelines, Python 3.9+ for the dispatch server (stdlib only).

## Config

```bash
cp config.example.yaml config.yaml
```

Paste the `models:` block from the `examples/` preset that matches your hardware, and fill any optional paths (`obsidian_vault`, `tailscale_hostname`). See [model-configuration.md](model-configuration.md).

## LiteLLM proxy

LiteLLM is the gateway every alias is served through. Point its config at your backend, mapping each of the 7 `model_name`s (the aliases) to a model. A minimal Ollama-backed LiteLLM `config.yaml`:

```yaml
model_list:
  - model_name: fast
    litellm_params: { model: ollama_chat/qwen2.5:1.5b, api_base: http://localhost:11434 }
  - model_name: max
    litellm_params: { model: ollama_chat/qwen2.5:32b, api_base: http://localhost:11434 }
  # one entry per alias: tiers (fast, balanced, max) + roles (structured, code, writing, reasoning)
```

Start it with a master key:

```bash
export LITELLM_MASTER_KEY=sk-local-xxxx
litellm --config /path/to/litellm-config.yaml --port 4000
```

Put the key where Hermes reads it:

```bash
echo "LITELLM_MASTER_KEY=sk-local-xxxx" >> ~/.hermes/.env
```

Prefer not to run LiteLLM? You can point agents at any OpenAI-compatible endpoint by setting `provider` and `base_url` accordingly, but the project assumes the LiteLLM alias layer. Cloud-only users: see `examples/models-cloud.yaml`.

## Pull models (local backends)

```bash
ollama pull qwen2.5:32b   # whatever your preset names
```

## Verify the path

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4000/v1/models   # 401 = up
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:11434/api/tags   # 200 = up
HERMES_DRY_RUN=1 ./agents/triage-router/run.sh "test"                      # composed command
./agents/triage-router/run.sh "We launch next week"                        # real call
```

## Optional surfaces

```bash
bin/gen-profiles.sh && hermes desktop      # desktop personas; see docs/hermes-desktop.md
python3 dispatch/server.py                 # mobile chat; see docs/tailscale-mobile.md
bin/run-pipeline.sh gtm-pipeline "brief"   # pipelines
```

## What each piece is

| Path | Role |
|------|------|
| `agents/<name>/` | one agent: `SOUL.md`, `agent.yaml`, `run.sh`, `README.md` |
| `lib/hermes-run.sh` | composes the real `hermes chat` call from `agent.yaml` |
| `lib/orchestrate.sh` | file-based state store plus pipeline executor |
| `hermes-home/config.yaml` | the minimal-context project Hermes home (tools off, and more) |
| `bin/gen-profiles.sh` | materialize agents as desktop profiles |
| `bin/run-pipeline.sh` | run a named pipeline end to end |
| `pipelines/*.json` | declarative pipeline definitions |
| `dispatch/` | the mobile dispatch server plus UI |

Want the wizard instead? See [diwm.md](diwm.md). Want containers? See [difm.md](difm.md).
