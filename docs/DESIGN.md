# Design

MacMD should feel like a quiet sheet of paper that happens to understand Markdown.

## Principles

1. **Native first.** System fonts (New York, SF Pro, SF Mono), the user's own accent color, standard menus,
   shortcuts and windows. Nothing is branded over the user's preferences.
2. **Ink on paper.** Neutral, low-glare backgrounds; text contrast ≥ 7:1; color is reserved for meaning
   (links, math).
3. **Syntax stays visible but quiet.** Markdown punctuation is drawn at 38 % opacity, so the source is honest
   and the content reads first.
4. **One bold gesture.** Large, tightly set H1s. Everything else is restrained.

## Themes

| Token | Paper (light / dark) | Clean (light / dark) | Mono (light / dark) |
|---|---|---|---|
| Background `--paper` | `#FAFAF8` / `#1A1B1E` | `#FFFFFF` / `#1E1E20` | `#F6F6F4` / `#18191B` |
| Text `--ink` | `#24262B` / `#E4E2DD` | `#1D1D1F` / `#E5E5E7` | `#222326` / `#DCDCD8` |
| Muted text `--ink-muted` | ink @ 66 % | ink @ 66 % | ink @ 66 % |
| Hairlines `--ink-faint` | ink @ 12 % | ink @ 11 % | ink @ 12 % |
| Code surface `--surface` | ink @ 4.5 % / 6 % | ink @ 4.5 % / 6 % | ink @ 5 % / 6 % |
| Body face | New York | SF Pro | SF Mono |
| Reader size / leading | 17 px / 1.65 | 16 px / 1.6 | 15 px / 1.7 |

Links use the system accent (`controlAccentColor`, CSS `AccentColor`); in dark mode they are mixed 35 % toward
the ink (`Theme.link`, CSS `--link`) because saturated accents glare on dark paper. Math uses a violet
(`#7A4BC2` / `#C3A6F2`) in the editor so it reads as "not prose".

Keep `App/Theme/Theme.swift` and `App/Resources/Web/reader.css` in sync when changing any of these values.

## Tokens

Shared by the editor (`Theme` constants) and the reader (CSS custom properties).

| Token | Value |
|---|---|
| Spacing | 4 · 8 · 12 · 16 · 24 · 32 · 48 |
| Radii | 6 inline (`--radius-inline`) · 10 block (`--radius-block`, `Theme.blockRadius`) · 14 panel (`--radius-panel`, `Theme.panelRadius`); task box 4 |
| Surface `--surface` | ink @ 4.5 % light (Mono 5 %), 6 % dark; `Theme.codeBackground` |
| Surface 2 `--surface-2` | ink @ 2.5 % light, 3.5 % dark |
| Quote bar `--quote-bar` | 2.5 pt, accent @ 45 % (`Theme.quoteBarWidth`, `quoteBarAlpha`) |
| Motion | 150 ms ease-out (`Theme.motion`); none under Reduce Motion |

Contrast targets (WCAG, checked for every theme and appearance by `ContrastTests`): text ≥ 7, muted text ≥ 4.5,
list markers ≥ 3, syntax markers ≥ 2 (decorative).

## Type scale

| Element | Editor (× body size) | Reader |
|---|---|---|
| H1 | 1.9, bold | 2.35 em, bold, −0.022 em tracking, 1.08 leading |
| H2 | 1.5, bold | 1.5 em, 650 |
| H3 | 1.25, semibold | 1.22 em, 650 |
| H4 | 1.1, semibold | 1.05 em, 650 |
| Code | 0.88, SF Mono | 0.86 em, SF Mono |

The measure is about 68 characters (Medium: 720 pt in the editor), configurable as Narrow, Medium, Wide or Full.

## Editor details

- Code blocks: rounded 10 pt surface (`--surface`) spanning the column; fences stay visible but faint. Read mode
  adds an inset `--ink-faint` hairline around blocks in dark mode; the editor does not.
- Quotes: a 2.5 pt accent bar (45 %), muted text, 16 pt indent.
- Lists: markers and task boxes in `listMarker` (text at 50%), matching the reader's muted `::marker`;
  wrapped lines hang under the item text.
- Focus mode dims everything but the current paragraph to 30 %; typewriter mode keeps the caret line centred.
