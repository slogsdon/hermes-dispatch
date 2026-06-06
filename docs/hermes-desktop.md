# Hermes desktop integration

The Hermes desktop app (and `hermes dashboard`, the web equivalent) has no concept of this repo's shell-wrapper agents, but it natively understands profiles. `bin/gen-profiles.sh` materializes one profile per agent so each shows up as a selectable chat persona.

## What a profile is

The desktop lists profiles by scanning `~/.hermes/profiles/<name>/`. A profile is three files:

| File | Role |
|------|------|
| `config.yaml` | pins the model plus the project's minimal-context settings |
| `SOUL.md` | the agent's system prompt, injected as the desktop chat persona |
| `.env` | a symlink to `~/.hermes/.env` so the LiteLLM key is available |

Profile names must match `^[a-z0-9][a-z0-9_-]{0,63}$`. The agent directory names already do.

## Generate profiles

```bash
bin/gen-profiles.sh --list        # preview: agent to model, no changes
bin/gen-profiles.sh               # generate or refresh a profile per agent
bin/gen-profiles.sh gtm-planner   # just one (or several)
bin/gen-profiles.sh --prefix hd-  # namespace them (hd-gtm-planner)
bin/gen-profiles.sh --remove      # delete only the profiles this script created
```

Each generated profile reuses `hermes-home/config.yaml` as its base, so the desktop chat behaves like the agent (same model, tools off, no reasoning block), with the model and turn budget pinned per agent. The agent's `SOUL.md` becomes the persona.

## Open the desktop

```bash
hermes profile list   # each agent appears with its pinned model
hermes desktop        # each agent is a selectable chat persona
# or the web equivalent:
hermes dashboard      # http://127.0.0.1:9119
```

## Safety

Each generated profile carries a `.hermes-agents-generated` marker file, so `--remove` can never delete a profile you made by hand. Secrets are never copied: `.env` is a symlink to the real `~/.hermes/.env`. The committed repo holds no keys.

## A limitation, stated plainly

Profiles expose individual agents, not the orchestrated pipelines. The desktop has no pipeline concept. For pipelines, use the CLI (`bin/run-pipeline.sh`) or the mobile dispatcher (`dispatch/server.py`), which run server-side so the LiteLLM key never reaches a browser.

## Pointing gen-profiles at a different home

By default profiles are written under `~/.hermes/profiles`. Override it:

```bash
HERMES_AGENTS_PROFILE_HOME=/path/to/home bin/gen-profiles.sh
```
