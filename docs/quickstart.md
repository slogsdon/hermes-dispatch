# Quickstart

From clone to first agent reply in a few minutes. Assumes you have Hermes Agent v0.15+ and a model backend (Ollama or LiteLLM) reachable.

## Clone and configure

```bash
git clone <this-repo> hermes-dispatch && cd hermes-dispatch
cp config.example.yaml config.yaml
```

Open `config.yaml` and paste in the `models:` block from the preset that matches your hardware:

```bash
# Apple Silicon (32 GB):  examples/models-m4-apple-silicon.yaml
# NVIDIA 24 GB:           examples/models-nvidia-24gb.yaml
# Cloud APIs:             examples/models-cloud.yaml
# One model, everything:  examples/models-minimal.yaml
```

Prefer to be walked through it? Run `./setup.sh`. See [diwm.md](diwm.md).

## Pull the models

For a local backend, pull the models your preset names. The minimal preset needs exactly one:

```bash
ollama pull qwen2.5:14b
```

## Verify the path

The model path is `hermes → LiteLLM (:4000) → backend`. Check it:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4000/v1/models   # 401 = up (needs key)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:11434/api/tags   # 200 = Ollama up
HERMES_DRY_RUN=1 ./agents/triage-router/run.sh "test"                      # inspect the composed command
```

`HERMES_DRY_RUN=1` prints the exact `hermes chat` command without calling a model. It's the fastest way to confirm wiring at zero GPU or RAM cost.

## Run an agent

```bash
# Inline input:
./agents/triage-router/run.sh "We need to launch the new toolkit next week"

# Piped input:
git diff main... | ./agents/pr-reviewer/run.sh
cat note.md      | ./agents/vault-distiller/run.sh
```

## Optional: go further

```bash
# Chain agents into a pipeline:
bin/run-pipeline.sh gtm-pipeline "Launch brief: a local-LLM agent toolkit for indie devs"

# Expose agents in the Hermes desktop app:
bin/gen-profiles.sh && hermes desktop

# Mobile chat over the whole roster:
python3 dispatch/server.py        # then open http://localhost:7777
```

## Troubleshooting

- `hermes: command not found`: Hermes isn't on `PATH` (usually `~/.local/bin`).
- 401 from LiteLLM: that means it's up. The proxy needs the master key, read from `~/.hermes/.env` (`LITELLM_MASTER_KEY`).
- `below the minimum 64,000 required`: Hermes' context floor. See [model-configuration.md](model-configuration.md#the-64k-context-floor).
- Agent returns a tool error: toolsets leaked in. The project disables them in `hermes-home/config.yaml`. Make sure you run via `./agents/<name>/run.sh`, not a bare `hermes` call.
