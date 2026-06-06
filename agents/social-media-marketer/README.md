# social-media-marketer

Turns a topic, link, or draft into **platform-tailored social posts** (LinkedIn, X, and an
optional X thread) written for a technical audience, no hype, no emoji-spam. Feeds a
`design-linkedin-post` / `design-instagram-post` design skills with the copy layer.

| | |
|---|---|
| **Alias** | `fast` |
| **Tools** | none |
| **Turns** | 1 |
| **Output** | `## LinkedIn` / `## X / Twitter` / optional `## X Thread` |

## Usage

```bash
./run.sh "New post on minimal local agents in Hermes, five flags, no framework. \
Link: example.com/post. Audience: backend devs."

# From a finished blog post:
cat draft.md |./run.sh
```

## Why this alias

Social copy is short and high-iteration, you want five quick variants, not one expensive
one. So this is right-sized to `fast`: fast and cheap, and the proxy forces
`think:false` so output is clean. The brief's rule in action: don't pin a 20B model to a
tweet.

## Tuning

- Want higher-quality, more distinctive copy (e.g. a flagship launch)? Switch
 `alias: writing` or `alias: max`.
- Pairs naturally downstream of `gtm-executor` (channel variants of the announcement) and
 `blog-drafter` (promote a finished post).
