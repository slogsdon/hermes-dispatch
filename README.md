# hermes-dispatch

Local-first agent dispatch for the [Hermes](https://hermes-agent.nousresearch.com) AI harness. Route and expand prompts across 28 specialized agents, reachable from your phone over Tailscale.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Hermes Agent](https://img.shields.io/badge/Hermes%20Agent-v0.15%2B-7c3aed)

There's no framework here and no hand-rolled agent loop. Hermes is the loop. Each agent is the harness constrained by a few per-agent flags plus one context-minimal project config, wrapped as a pure `stdin → stdout` shell script. The model you route to is the quality lever: cheap models for triage and extraction, one big model reserved for the work that's actually hard.

## What it does

- Runs 28 narrow agents. Each is a system prompt plus a model alias. They cover writing, code review, SEO, GTM, sales, legal, finance, knowledge work, and automation.
- Gives you one chat box on your phone. A fast model picks the right agent and rewrites your terse message into a tuned prompt, then the chosen agent runs and streams back.
- Stays portable. Every agent names an alias (`max`, `code`, `structured`), never a model. Point those 7 aliases at MLX, CUDA, cloud, or a single model. Same agents, any backend.

## Prerequisites

- [Hermes Agent](https://hermes-agent.nousresearch.com) v0.15+ on your `PATH`.
- A model backend: [Ollama](https://ollama.com) for local models, [LiteLLM](https://docs.litellm.ai) for the proxy and cloud. The path is `hermes → LiteLLM (:4000) → backend`.
- `jq` for pipelines, Python 3.9+ for the dispatch server (stdlib only).
- [Tailscale](https://tailscale.com) if you want phone access. Optional.

## Setup: pick a path

| Path | For | Start here |
|------|-----|-----------|
| DIY | "I want full control, I'll wire it myself." | [docs/diy.md](docs/diy.md) |
| Do it With Me | "Walk me through it." | `./setup.sh`, then [docs/diwm.md](docs/diwm.md) |
| Do it For Me | "Just run it in containers." | [docs/difm.md](docs/difm.md) (`docker/`) |

```bash
git clone <this-repo> hermes-dispatch && cd hermes-dispatch
cp config.example.yaml config.yaml   # then edit, or:
./setup.sh                           # interactive wizard (DIWM)
```

## The agents

Every agent maps to one of 7 aliases: three capability tiers (`fast`, `balanced`, `max`) and four task roles (`structured`, `code`, `writing`, `reasoning`) that default to a tier. What backs each is your choice. See [docs/model-configuration.md](docs/model-configuration.md).

| Agent | Purpose | Alias |
|-------|---------|-------|
| [`blog-drafter`](agents/blog-drafter/) | First-draft long-form blog prose from an outline | `writing` |
| [`social-media-marketer`](agents/social-media-marketer/) | Topic or draft to platform-tailored LinkedIn and X posts | `fast` |
| [`status-update-writer`](agents/status-update-writer/) | done/blocked/next bullets to a client status update | `writing` |
| [`devrel-sample`](agents/devrel-sample/) | API plus capability description to a developer code sample | `code` |
| [`pr-reviewer`](agents/pr-reviewer/) | Unified diff to a five-axis code review | `max` |
| [`seo-reviewer`](agents/seo-reviewer/) | Page or draft to a qualitative on-page SEO and AEO audit | `max` |
| [`seo-tester`](agents/seo-tester/) | Page to machine-readable pass/fail SEO checks (JSON) | `structured` |
| [`gtm-planner`](agents/gtm-planner/) | Product brief to a decision-ready go-to-market plan | `max` |
| [`gtm-executor`](agents/gtm-executor/) | GTM plan to paste-ready launch assets | `writing` |
| [`lead-designer`](agents/lead-designer/) | Brief to design direction or critique (text specs) | `max` |
| [`prospect-researcher`](agents/prospect-researcher/) | Company or contact to a sales research brief | `max` |
| [`discovery-prep`](agents/discovery-prep/) | Prospect plus goal to a pre-call discovery plan | `max` |
| [`proposal-writer`](agents/proposal-writer/) | Scope brief to a structured client proposal | `writing` |
| [`followup-drafter`](agents/followup-drafter/) | Last interaction to a follow-up email | `writing` |
| [`scope-creep-detector`](agents/scope-creep-detector/) | Agreed scope plus new request to an in/out call | `reasoning` |
| [`contract-reviewer`](agents/contract-reviewer/) | Contract or vendor agreement to a severity-ranked risk pass | `max` |
| [`tos-reviewer`](agents/tos-reviewer/) | Terms of service to a risk pass before you agree | `max` |
| [`privacy-checker`](agents/privacy-checker/) | Privacy policy or DPA to a data map plus gaps | `max` |
| [`cashflow-summarizer`](agents/cashflow-summarizer/) | Transactions to a weekly cashflow summary | `reasoning` |
| [`invoice-tracker`](agents/invoice-tracker/) | Invoice email to vendor, amount, due date, and status | `structured` |
| [`expense-classifier`](agents/expense-classifier/) | Transaction descriptions to tax-relevant categories | `structured` |
| [`triage-router`](agents/triage-router/) | One item to a routing decision (minified JSON) | `structured` |
| [`inbox-triage`](agents/inbox-triage/) | Batch of emails to a classified enum plus urgency | `structured` |
| [`vault-distiller`](agents/vault-distiller/) | Long note to atomic concepts, `[[wikilinks]]`, and tags | `max` |
| [`decision-journal`](agents/decision-journal/) | A decision to a durable note written for future-you | `reasoning` |
| [`meeting-to-actions`](agents/meeting-to-actions/) | Notes or transcript to decisions plus action items | `reasoning` |
| [`retro-generator`](agents/retro-generator/) | Project notes to a structured retrospective | `reasoning` |
| [`weekly-review-synthesis`](agents/weekly-review-synthesis/) | A week of notes to a candid weekly review | `max` |

Run one directly:

```bash
git diff main... | ./agents/pr-reviewer/run.sh
./agents/triage-router/run.sh "We need to launch the toolkit next week"
HERMES_DRY_RUN=1 ./agents/blog-drafter/run.sh "test"   # inspect the composed command
```

## Beyond single agents

- Chain agents into pipelines over a shared file-based state store: `bin/run-pipeline.sh gtm-pipeline "Launch brief: ..."`. See [pipelines/](pipelines/).
- Expose every agent as a desktop chat persona: `bin/gen-profiles.sh`, then `hermes desktop`. See [docs/hermes-desktop.md](docs/hermes-desktop.md).
- Reach the roster from your phone: `python3 dispatch/server.py` plus Tailscale. See [docs/tailscale-mobile.md](docs/tailscale-mobile.md).

## Documentation

| Doc | What it covers |
|-----|----------------|
| [docs/quickstart.md](docs/quickstart.md) | Fastest path from clone to first agent reply |
| [docs/model-configuration.md](docs/model-configuration.md) | How aliases work, what backs them, hardware tradeoffs |
| [docs/agents.md](docs/agents.md) | Full agent roster with descriptions and recommended aliases |
| [docs/hermes-desktop.md](docs/hermes-desktop.md) | Profile registration, desktop and dashboard visibility |
| [docs/tailscale-mobile.md](docs/tailscale-mobile.md) | Tailscale Serve setup for phone access |
| [docs/obsidian.md](docs/obsidian.md) | Optional Obsidian save-to-vault integration |
| [docs/diy.md](docs/diy.md), [docs/diwm.md](docs/diwm.md), [docs/difm.md](docs/difm.md) | The three setup tiers |

## License

[MIT](LICENSE).
