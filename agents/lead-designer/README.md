# lead-designer

A senior product designer that gives **design direction** (from a brief) or **critique**
(of a text-described design, DESIGN.md, tokens, component markup/CSS, layout spec). Opinion
backed by principle, ruthless on hierarchy and accessibility. Pairs with Shane's `design-*`
skills, which produce exactly the text artifacts this reviews.

| | |
|---|---|
| **Alias** | `quality` → `qwen3.6:35b-mlx` (21.9 GB) |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | `## Read` / Hierarchy / Typography / Color / Components / Findings / Next Moves |

## Usage

```bash
# Critique an existing design spec:
cat design/acme/DESIGN.md | ./run.sh
cat design/acme/tokens.css | ./run.sh

# Get direction from a brief:
./run.sh "Brief: landing page for hermes-agents, backend-dev audience, dark theme, \
minimal, must make 'free + local' the hero."
```

## Scope (important)

This works from **text, not pixels**, it has no vision tool, so it judges structure,
tokens, copy, spacing logic, and stated intent, and it will tell you when a call needs the
actual rendered pixels. To give it eyes, enable Hermes' `vision` toolset (`toolsets: vision`
in `agent.yaml`, bump `max_turns`) and pass an image, at the cost of the minimal, fast path.

## Why this alias

Design taste is the one judgment task that earns `quality` (qwen3.6:35b-mlx), best local
holistic judgment, long context for whole-spec review, and its thinking is routed to a
separate channel so the visible critique stays clean (no `strip_think` needed). Fits *alone*
on 32 GB; don't co-resident it with another large model.

## Tuning

- For a cheaper, gate-style design review, switch `alias: review` (granite4.1:8b).
- WCAG AA contrast checks are inferred from stated colors only, verify rendered contrast
  with a real checker before shipping.
