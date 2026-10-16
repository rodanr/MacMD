# UI refinement — design spec

_2026-10-15 · status: shipped in 0.3.0 (follow-up fixes in 0.3.1)_

## Goal

Make MacMD feel more modern and refined **without adding features**. Direction: **editorial calm**. Keep the
"ink on paper" identity (New York serif, quiet surfaces, the system accent) and polish typography, spacing,
surfaces and window chrome so the editor, Read mode and the window read as one design.

## Problems found

| Area | Problem | Where |
|---|---|---|
| Read mode code | Uneven, heavy padding: the trailing newline from cmark ends up inside `<pre><code>` | `HTMLRenderer.visitCodeBlock` |
| Diagrams | Stock Mermaid theme: hard dark boxes, a serif font, labels on lines | `reader.js` `renderDiagrams` |
| Diagrams (bug) | Not redrawn when the system switches light/dark | `reader.js` |
| Tables | No container and no header surface | `reader.css` |
| Task boxes | Circles, which read as radio buttons | `reader.css` |
| Consistency | Code radius and quote bar differ between the editor and Read mode | `BlockDecoration.swift`, `reader.css` |
| Contrast | Syntax markers at 28% ink | `Theme.syntaxMarker` |
| Sidebar | No hierarchy cues; current heading highlighted in Edit mode only | `OutlineView.swift` |
| Motion | No Reduce Motion support | `DocumentView.swift`, `HUD.swift` |

## Tokens

Recorded in `docs/DESIGN.md`, mirrored in `Theme.swift` and `reader.css`.

| Token | Value |
|---|---|
| Spacing | 4 · 8 · 12 · 16 · 24 · 32 · 48 |
| Radius | inline 6 · block 10 · panel 14 · task box 4 |
| `--surface` | ink 4.5% (light) / 6% (dark): code |
| `--surface-2` | ink 2.5% / 3.5%: table headers |
| Hairline | `--ink-faint` |
| Quote bar | 2.5 pt, accent 45% (both modes) |
| Syntax markers | ink about 38% (decorative, ≥ 2:1) |
| Motion | 150 ms ease-out; none with Reduce Motion |

Contrast targets: body ≥ 7:1, muted ≥ 4.5:1, list markers ≥ 3:1, syntax markers ≥ 2:1 (decorative), in every theme and appearance.

## Read mode

- **Code blocks:** the renderer drops the one trailing newline. 0.9em × 1.1em padding, radius 10, line-height 1.55,
  hairline border in dark appearance, thin scrollbars. Inline code: radius 6, tighter padding.
- **Tables:** the renderer wraps each table in `<div class="table">`. The wrapper has radius 10, a hairline
  border and horizontal scrolling. The header uses `--surface-2`.
- **Task boxes:** rounded squares (radius 4); checked boxes filled with the accent, with a check drawn in CSS.
- **Quotes:** shared bar, 1em padding; Paper italic, Clean and Mono roman.
- **Rhythm:** `h1` ≈ 2.15em, more space above `h2`, margins from the scale, `scroll-margin-top`.
- **Mermaid:** `theme: "base"` with `themeVariables` from the page tokens, `system-ui` labels, rounded nodes.
  The source is kept in `data-source`, and diagrams are redrawn on appearance changes.
- **Images:** radius 6; hairline outline in dark appearance.
- **Links and selection:** thinner underline that brightens on hover; softer selection tint.
- **Exports** share the CSS and must still look right in light appearance (HTML and PDF).

## Editor

- **Code backgrounds:** radius 10; 12 pt inner indent on code lines.
- **Quote bar:** shared token. **Syntax markers:** about 38% ink.
- **Rhythm:** heading spacing from the scale; attribute-only changes. The styling consistency fuzz must stay green.
- **Focus mode:** dimmed text around 35% ink.
- **Empty document:** "Start writing…" placeholder drawn by the editor, never part of the text.

## Window chrome

- **Status bar:** keep `.bar`, add a top hairline, 11 pt secondary text, spacing from the scale; chips use the
  panel radius. The zoom label stays visible.
- **Outline:** hairline indent guides per level, level weights, and a soft accent pill on the current heading,
  in Edit mode and in Read mode (via the reader's `topLine`).
- **Files:** secondary icons, the current file as a pill.
- **Motion:** HUD, mode crossfade and sidebar animation respect Reduce Motion.
- **Toolbar, Settings, About:** alignment and spacing only.

## Out of scope

New features: hiding syntax, callouts, a command palette, new themes or settings.

## Testing

- MacMDKit tests for the renderer changes (code newline, table wrapper), written first. The cmark differential
  tests stay green.
- `make test-app` (incremental vs full styling) green, with raised seeds once.
- A design-review UI test captures the editor and Read mode for every theme in light and dark, plus the sidebar,
  the status bar and Settings, for visual review.
- Appearance switch with a diagram open: the diagram redraws in the new palette.
- Export UI tests pass; an exported PDF is checked by eye.

## Outcome

Shipped in 0.3.0. Where the result differs from this spec:

- **Task lists** use a hanging indent (box positioned at the start of the item), not a grid: a grid split items
  with inline formatting onto separate rows. Nested task lists sit under their parent item.
- **Quote bar** in the editor is drawn as square segments that exactly span each line, so a quote has no seams.
- **Editor code surface** is derived from each theme's ink (4.5 % light, Mono 5 %, 6 % dark), like Read mode;
  the dark hairline border is Read mode only.
- **Syntax markers** are held to ≥ 2:1 contrast (decorative), not 3:1; list markers keep ≥ 3:1.
- **Focus mode** was reworked in 0.3.1: dimmed text at about 55 % strength (not 35 %), the paragraph just
  written stays bright on a blank line, and shades no longer paint over the focused paragraph.
- **Design review screenshots** come from CI (`DesignReviewUITests`, 1024×768), whose results are uploaded for
  pull requests.

Deferred: editor heading spacing from the spacing scale; a spacing pass on the toolbar, Settings and About.
