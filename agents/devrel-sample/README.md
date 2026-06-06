# devrel-sample

Developer-advocacy code-sample generator. Turns an API + capability description into a
short, runnable, copy-pasteable sample plus integrator notes, the daily bread of DevRel
work at Global Payments (docs snippets, blog code, integration guides).

| | |
|---|---|
| **Alias** | `code` → `qwen2.5-coder:14b` (9.0 GB) |
| **Tools** | none |
| **Turns** | 1 (one-shot) |
| **Output** | one fenced code block + `Notes:` bullets |

## Usage

```bash
# Inline spec:
./run.sh "TypeScript: capture an authorized payment with the Acme Payments SDK, \
amount in minor units, handle the declined-card path."

# From a file (e.g. an endpoint spec or ticket):
cat endpoint-spec.md | ./run.sh

# See the exact hermes command without running it:
HERMES_DRY_RUN=1 ./run.sh "..."
```

## Why this alias

`code` (qwen2.5-coder:14b) is the strongest local coder and is **non-reasoning**, so it
emits clean output with no chain-of-thought to strip. At 9 GB it fits with headroom, no
need to reach for `quality`. For pure snippets, no tools are needed; the spec is pasted in.

## ⚠️ Security caveat

This is a **sample generator**, not a security reviewer. In testing, qwen2.5-coder produced
a webhook-signature handler that got the constant-time comparison, 401s, idempotency, and
env-secret right, but **hashed the re-serialized JSON instead of the raw request body**, a
critical flaw that breaks verification. Local code models write plausible-but-subtly-broken
crypto. **Treat any auth/crypto/signature sample as a draft and have it reviewed** (e.g. pipe
it through `pr-reviewer`, which runs on `quality` and catches exactly this class of bug).

## Tuning

- Want the agent to read files itself instead of pasting? Set `toolsets: file` in
  `agent.yaml` and bump `max_turns` to ~3.
- For a heavier, multi-file scaffold, switch `alias: quality`, but mind the 32 GB ceiling.
