# Agent roster

28 narrow agents. Each is a pure `stdin → stdout` shell wrapper: a system prompt (`SOUL.md`), a declarative spec (`agent.yaml`), and a thin `run.sh`. None names a model. Each names an alias (the recommended tier below). Remap aliases in `config.yaml` to change what backs them. See [model-configuration.md](model-configuration.md).

```bash
./agents/<name>/run.sh "input"        # inline
cat input.md | ./agents/<name>/run.sh # piped
HERMES_DRY_RUN=1 ./agents/<name>/run.sh "x"   # show composed command, don't run
```

## Writing and content

| Agent | Purpose | Alias |
|-------|---------|-------|
| `blog-drafter` | First-draft long-form blog prose from an outline or notes | `write` |
| `social-media-marketer` | Topic, link, or draft to LinkedIn, X, and thread posts | `chat` |
| `status-update-writer` | done/blocked/next bullets to a polished client status update | `write` |

## Code and review

| Agent | Purpose | Alias |
|-------|---------|-------|
| `devrel-sample` | API plus capability description to a developer code sample plus notes | `code` |
| `pr-reviewer` | Unified diff to a five-axis review (correctness, readability, and more) | `quality` |

## SEO and AEO

| Agent | Purpose | Alias |
|-------|---------|-------|
| `seo-reviewer` | Page or draft to a qualitative on-page SEO and AEO audit | `quality` |
| `seo-tester` | Page to machine-readable per-check pass/fail JSON | `pipeline` |

## Go-to-market and design

| Agent | Purpose | Alias |
|-------|---------|-------|
| `gtm-planner` | Product or feature brief to a decision-ready GTM plan | `quality` |
| `gtm-executor` | GTM plan to paste-ready launch assets (announcement, email, CTA) | `write` |
| `lead-designer` | Brief to design direction, or artifact to design critique | `quality` |

## Sales pipeline

| Agent | Purpose | Alias |
|-------|---------|-------|
| `prospect-researcher` | Company or contact to a sales-call research brief | `quality` |
| `discovery-prep` | Prospect plus goal to a pre-call discovery plan | `quality` |
| `proposal-writer` | Scope brief to a structured client proposal | `write` |
| `followup-drafter` | Last interaction to a concise follow-up email | `write` |
| `scope-creep-detector` | Agreed scope plus new request to an in/out call plus rationale | `analyze` |

## Legal and compliance

| Agent | Purpose | Alias |
|-------|---------|-------|
| `contract-reviewer` | Contract or vendor agreement to a severity-ranked risk pass | `quality` |
| `tos-reviewer` | Terms of service to a risk pass before you agree | `quality` |
| `privacy-checker` | Privacy policy or DPA to a data map plus gaps | `quality` |

## Finance

| Agent | Purpose | Alias |
|-------|---------|-------|
| `cashflow-summarizer` | Transactions (paste or CSV) to a weekly cashflow summary | `analyze` |
| `invoice-tracker` | Invoice email to vendor, amount, currency, due date, and status | `pipeline` |
| `expense-classifier` | Transaction descriptions to tax-relevant categories | `pipeline` |

## Automation and triage

| Agent | Purpose | Alias |
|-------|---------|-------|
| `triage-router` | One item to a routing decision (single-line minified JSON) | `pipeline` |
| `inbox-triage` | Batch of emails to a classified enum plus urgency | `pipeline` |

## Knowledge work

| Agent | Purpose | Alias |
|-------|---------|-------|
| `vault-distiller` | Long note to atomic concepts, `[[wikilinks]]`, and tags | `quality` |
| `decision-journal` | A decision to a durable note written for future-you | `analyze` |
| `meeting-to-actions` | Notes or transcript to decisions plus action items | `analyze` |
| `retro-generator` | Project notes to a structured retrospective | `analyze` |
| `weekly-review-synthesis` | A week of notes to a candid weekly review | `quality` |

## agent.yaml keys

Each agent's behavior is declared in `agent.yaml`. `lib/hermes-run.sh` composes the real `hermes chat` command from it.

| Key | Default | Meaning |
|-----|---------|---------|
| `alias` | *(required)* | the model alias to pin with `-m` |
| `provider` | `litellm` | inference provider |
| `max_turns` | `1` | tool-loop cap (`--max-turns`) |
| `toolsets` | `""` | `-t` allowlist; tools are disabled project-wide anyway |
| `ignore_rules` | `true` | `--ignore-rules` (strip ambient persona, memory, skills) |
| `ignore_user_config` | `false` | `--ignore-user-config` (full isolation) |
| `quiet` | `true` | `-Q` (suppress banner) |
| `parse_last_line` | `false` | keep only the last stdout line (single-line JSON) |
| `strip_think` | `false` | remove `<think>...</think>` spans |
| `strip_reasoning` | `false` | remove a rendered `┌─ Reasoning` block (needs `answer_anchor`) |
| `answer_anchor` | none | literal first output line; quote it (a leading `#` is a YAML comment) |

### Env overrides

| Var | Effect |
|-----|--------|
| `AGENT_HERMES_MODEL` | override the alias for one run |
| `AGENT_HERMES_PROVIDER` | override the provider |
| `HERMES_DRY_RUN=1` | print the composed command, don't run it |
| `HERMES_AGENTS_HOME` | runtime Hermes home (default `~/.cache/hermes-agents-home`) |
| `HERMES_AGENTS_NO_HOME=1` | bypass the project home, use `~/.hermes` |

## Why agents stay pure

Hermes has no per-agent manifest format. Per-agent behavior is set by CLI flags. `agent.yaml` is this project's convention: a declarative record the runner reads to build the real command. Project-wide behavior that flags can't reach (toolsets off, reasoning render off, no memory, skills, or persona) lives once in `hermes-home/config.yaml`. Because each agent is just `stdin → stdout`, it never has to know it's part of a pipeline, a desktop profile, or the mobile dispatcher.
