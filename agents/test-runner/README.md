# test-runner

A **shell-enabled scout** that discovers *how* to run a project's tests when the standard
detectors can't — non-standard layouts, custom scripts, monorepos, unusual runners. It
inspects the project and reports the exact command for each test layer (unit, integration,
Playwright). It is discovery, not the source of truth.

| | |
|---|---|
| **Alias** | `max` |
| **Tools** | `terminal` (the only agent here that calls tools) |
| **Turns** | up to 12 (inspect → read → decide loop) |
| **Reads** | the project to inspect (path / hints) — runs in the project's directory |
| **Writes** | one line of JSON: `{"stack","unit_cmd","integration_cmd","playwright_cmd","notes"}` |

## Usage

Run it with the project as the current directory so its shell commands operate there:

```bash
( cd /path/to/project && /path/to/test-runner/run.sh "discover the test commands" )
```

## Role

The hybrid fallback for the validate step of the dev-workflow pipeline:
**brief → directions → plan → [gate] → tests → test-audit → code → validate → review/security → release/describe.**
The orchestrator re-runs the discovered commands deterministically to capture the
authoritative exit code — the model never self-reports pass/fail, it only finds the right
command. Its `terminal` toolset is enabled by a scoped per-agent home (`hermes-home/config.yaml`);
every other agent runs fully tool-free. Tool use needs a reliable reasoner, so it runs on `max`.
