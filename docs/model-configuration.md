# Model configuration

The most important idea in this project: agents name aliases, not models.

## The 8 aliases

Every agent's `agent.yaml` pins one alias. There are eight, ordered roughly by cost and capability:

| Alias | Intended role | Typical use |
|-------|---------------|-------------|
| `classify` | tiny, sub-second triage and routing | enum classification |
| `chat` | fast conversational, no thinking | social posts, short replies |
| `review` | cheap review and gating | first-pass findings |
| `code` | code generation | API samples, codegen |
| `analyze` | reasoning, arithmetic, judgment | numbers, decisions |
| `pipeline` | fast structured output, no thinking | JSON, extraction, drafts |
| `write` | long-form prose | proposals, announcements |
| `quality` | best quality, reserved for hard steps | strategy, synthesis, design |

The alias is the cost and quality dial. An agent that says `alias: quality` uses whatever you've mapped `quality` to: a 35B MLX model, Claude Sonnet, or (in the minimal preset) the same 14B as everything else.

## Where the mapping lives

There are two layers, by design.

`config.yaml` (the `models:` block in this repo) is the human-facing alias-to-model map. Copy a preset from `examples/` into it. `setup.sh` and the Docker `bootstrap.sh` generate the LiteLLM config from this.

The LiteLLM proxy is the actual gateway. It serves each alias as a `model_name` and routes to the backend. Everything flows `hermes → LiteLLM (:4000) → backend`.

`hermes-home/config.yaml` declares the per-alias context lengths Hermes uses and disables every toolset. It's the minimal-context lever and rarely needs editing.

## Model string format

`config.yaml` values are LiteLLM model strings:

| Backend | Format | Example |
|---------|--------|---------|
| Ollama (local) | `ollama_chat/<tag>` | `ollama_chat/qwen2.5:14b` |
| OpenAI | `openai/<model>` | `openai/gpt-4o-mini` |
| Anthropic | `anthropic/<model>` | `anthropic/claude-3-5-sonnet-latest` |
| Groq | `groq/<model>` | `groq/llama-3.3-70b-versatile` |

Use `ollama_chat/`, not `ollama/`, for Ollama. The chat-completions path handles stop tokens and tool framing correctly. You still `ollama pull <tag>` without the prefix; the prefix is only LiteLLM's routing hint.

## Hardware tradeoffs

The presets in `examples/` encode the tradeoff:

- Apple Silicon (32 GB unified) shares memory with the OS. Keep the resident model at 20 GB or under, so the big `quality` model runs alone. MLX builds are fastest.
- NVIDIA 24 GB is dedicated VRAM with a hard 24 GB wall. `quality` is a 32B at Q4 (about 19 GB) that fits by itself.
- Cloud has no memory limits but costs per token. Keep the high-volume aliases (`classify`, `pipeline`) cheap; reserve frontier models for `quality` and `code`.
- Minimal uses one model for all 8 aliases. Simplest, but loses the tiering.

Pipelines are sequential by construction, so a chain that uses `quality` then `write` then `chat` never co-resides the big models. Each unloads before the next loads. The roster respects your memory ceiling for free.

## The 64K context floor

Hermes Agent rejects any model whose declared `context_length` is below 64,000 ("below the minimum 64,000 required"). Some models are tuned to a smaller real `num_ctx` for throughput or memory. The fix lives in `hermes-home/config.yaml`, which overrides the declared `context_length` to 64000 for those aliases. It only ever raises a number Hermes reads, never the real backend `num_ctx`. This is harmless for cloud models, whose real context is far larger. If you map an alias to a small-context local model, keep that agent's inputs under the real `num_ctx`.

## Why model choice is the quality lever

This project has no clever orchestration framework. The whole advantage is in routing the right model to the right task. A 1.2B for triage costs almost nothing and is plenty. The 35B `quality` model is reserved for the few steps where judgment actually matters: note synthesis, GTM strategy, design critique. Swapping a preset re-tiers the whole roster at once.
