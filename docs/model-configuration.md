# Model configuration

The most important idea in this project: agents name aliases, not models. There are two kinds of alias, on two axes.

## The two axes

**Tiers (required)** are the capability and cost spine. A consumer only has to map these three:

| Tier | Role |
|------|------|
| `fast` | smallest and quickest: triage, routing, extraction, short chat |
| `balanced` | mid capability: a solid default for most work |
| `max` | largest: best quality, reserved for high-consequence work |

**Task roles (optional)** are specializations. Point one at a dedicated model, or leave it blank to inherit its default tier:

| Role | Inherits | When to set it |
|------|----------|----------------|
| `structured` | `fast` | a model that reliably emits clean JSON / fixed schemas |
| `code` | `balanced` | a dedicated coding model |
| `writing` | `balanced` | a prose-tuned model for long-form |
| `reasoning` | `max` | a chain-of-thought model for analysis and arithmetic |

So the minimum to get running is three model strings (the tiers). The four roles fall back to a tier until you give them their own model. Every agent's `agent.yaml` pins one of these seven aliases.

## Why two axes

The naive approach mixes capability and task on one list (`quality`, `code`, `pipeline`, ...), which forces a newcomer to learn an opaque taxonomy. Splitting them means:

- A consumer maps **3 tiers** and everything works.
- Power users add task models only where a specialist beats the tier.
- The alias an agent names tells you *both* how heavy it is (tier) and what it's for (role), without a lookup table.

## Where the mapping lives

Two layers, by design.

`config.yaml` (the `models:` block in this repo) is the human-facing alias-to-model map. Copy a preset from `examples/` into it. `setup.sh` and the Docker `bootstrap.sh` read it (or the matching `MODEL_*` env vars) and generate the gateway config, applying role inheritance.

The **gateway** is the actual router. The reference is [LiteLLM](https://docs.litellm.ai): it serves each alias as a `model_name` and routes to the backend, unifying local and cloud under one key. But the project only needs an OpenAI-compatible `/v1/chat/completions` endpoint, so Ollama's native `/v1`, vLLM, LM Studio, OpenRouter, or LocalAI work too. Everything flows `hermes → gateway (:4000) → backend`.

`hermes-home/config.yaml` declares the per-alias context lengths Hermes uses and disables every toolset. It's the minimal-context lever and rarely needs editing, except to raise a context length when you map an alias to a longer-context model.

## Model string format

`config.yaml` values are gateway model strings:

| Backend | Format | Example |
|---------|--------|---------|
| Ollama (local) | `ollama_chat/<tag>` | `ollama_chat/qwen2.5:14b` |
| OpenAI | `openai/<model>` | `openai/gpt-4o-mini` |
| Anthropic | `anthropic/<model>` | `anthropic/claude-3-5-sonnet-latest` |
| Groq | `groq/<model>` | `groq/llama-3.3-70b-versatile` |

Use `ollama_chat/`, not `ollama/`, for Ollama. The chat-completions path handles stop tokens and tool framing correctly. You still `ollama pull <tag>` without the prefix; the prefix is only the gateway's routing hint.

## Hardware tradeoffs

The presets in `examples/` map the same seven aliases to different backends:

- **Apple Silicon (32 GB unified)** shares memory with the OS. Keep the resident model at 20 GB or under, so the `max` tier runs alone. MLX builds are fastest.
- **NVIDIA 24 GB** is dedicated VRAM with a hard wall. `max` is a 32B at Q4 (about 19 GB) that fits by itself.
- **Cloud** has no memory limits but costs per token. Keep `fast` and `structured` cheap; reserve frontier models for `max` and `code`.
- **Minimal** points all seven aliases at one model. Simplest, loses the tiering.

Pipelines are sequential by construction, so a chain that uses `max` then `writing` then `fast` never co-resides the big models. Each unloads before the next loads. The roster respects your memory ceiling for free.

## The 64K context floor

Hermes Agent rejects any model whose declared `context_length` is below 64,000 ("below the minimum 64,000 required"). Some models are tuned to a smaller real `num_ctx` for throughput or memory. The fix lives in `hermes-home/config.yaml`, which sets the declared `context_length` to at least 64000 for those aliases. It only ever raises a number Hermes reads, never the real backend `num_ctx`. Harmless for cloud models, whose real context is far larger. If you map an alias to a small-context local model, keep that agent's inputs under the real `num_ctx`.

## Why model choice is the quality lever

This project has no clever orchestration framework. The whole advantage is in routing the right model to the right task. A 1.5B on `fast` costs almost nothing and is plenty for triage. The `max` tier is reserved for the few steps where judgment actually matters: note synthesis, GTM strategy, design critique. Swapping a preset re-tiers the whole roster at once.
