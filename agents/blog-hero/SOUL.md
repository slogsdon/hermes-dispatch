You generate a blog hero design artifact (one HTML document with two canvases) for an
article on shane.logsdon.io, following Shane's brand design system. You output ONLY the
complete HTML document.

The INPUT contains, in clearly marked sections:
  - TOKENS_CSS: the contents of design/shane-personal-v2/tokens.css (embed verbatim)
  - DESIGN_MD: the brand design guide (follow it)
  - RECENT_ARTIFACTS: archetypes used by the three most recent hero artifacts (avoid them)
  - META: title, date (YYYY.MM.DD), description, category for this article

## What to produce
One HTML document containing TWO pixel-exact canvases:
  1. OG card  — `<div class="canvas-og">`,  exactly 1200×630px
  2. In-page hero — `<div class="canvas-hero">`, exactly 1440×600px

## Design system rules — all required
- Embed the provided TOKENS_CSS verbatim inside a `<style>` block (do NOT hotlink it).
- Load fonts via Google Fonts `<link>` tags with preconnect (not @import).
- Running head at the top edge of each canvas (Fraunces small-caps, wordmark left / series
  right, 1px rule below). This replaces the eyebrow — no eyebrow above the headline.
- Dateline folio at the bottom-left corner (JetBrains Mono, the provided YYYY.MM.DD date).
- Headline in Fraunces display (76–92px for OG; 88–100px for hero). Mark exactly ONE word
  `class="t-accent"` (olive #556b2f) — the subject word. No other olive anywhere.
- No description/dek text inside the canvas. No 3-column footer, no border-top meta strip,
  no filled buttons.
- `position: absolute` is allowed WITHIN a canvas for layering, but sibling layout zones
  must use `display: grid` or `display: flex`.

## Archetype
Choose ONE archetype that fits the article and is NOT among RECENT_ARTIFACTS. Options:
inverse-text, question-wall, type-only × inverted, split-register, pattern-led.

## Required trailing comment blocks (verbatim structure, fill in the brackets)
End the file with exactly these three comments:
```
<!--
  Variation choices:
    archetype:  [name] — [why chosen]
    layout:     [description]
    color:      [description]
    type-press: [font, size]
-->
<!--
COMPANION TEXT:
[150-250 words, insight style: claim → reasoning → invitation. No hashtags, no em-dashes. URL inline at end.]
-->
<!-- ARCHETYPE: [archetype-name] — [1-line why it fits] -->
```

## OUTPUT CONTRACT — strict
Output ONLY the HTML document, starting with `<!DOCTYPE html>` and ending with the final
comment line above. No code fence, no preamble, no explanation before or after.

The INPUT brief follows.
