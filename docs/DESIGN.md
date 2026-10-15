# Design

MacMD should feel like a quiet sheet of paper that happens to understand Markdown.

## Principles

1. **Native first.** System fonts (New York, SF Pro, SF Mono), the user's own accent color, standard menus,
   shortcuts and windows. Nothing is branded over the user's preferences.
2. **Ink on paper.** Neutral, low-glare backgrounds; text contrast ≥ 7:1; color is reserved for meaning
   (links, math).
3. **Syntax stays visible but quiet.** Markdown punctuation is drawn at 28 % opacity, so the source is honest
   and the content reads first.
4. **One bold gesture.** Large, tightly set H1s. Everything else is restrained.

## Themes

| Token | Paper (light / dark) | Clean (light / dark) | Mono (light / dark) |
|---|---|---|---|
| Background `--paper` | `#FAFAF8` / `#1A1B1E` | `#FFFFFF` / `#1E1E20` | `#F6F6F4` / `#18191B` |
| Text `--ink` | `#24262B` / `#E4E2DD` | `#1D1D1F` / `#E5E5E7` | `#222326` / `#DCDCD8` |
| Muted text `--ink-muted` | ink @ 62 % | ink @ 60 % | ink @ 60 % |
| Hairlines `--ink-faint` | ink @ 12 % | ink @ 11 % | ink @ 12 % |
| Code surface `--surface` | ink @ 4.5 % | ink @ 4.5 % | ink @ 5 % |
| Body face | New York | SF Pro | SF Mono |
| Reader size / leading | 17 px / 1.65 | 16 px / 1.6 | 15 px / 1.7 |

Links use the system accent (`controlAccentColor`, CSS `AccentColor`); in dark mode they are mixed 35 % toward
the ink (`Theme.link`, CSS `--link`) because saturated accents glare on dark paper. Math uses a violet
(`#7A4BC2` / `#C3A6F2`) in the editor so it reads as "not prose".

Keep `App/Theme/Theme.swift` and `App/Resources/Web/reader.css` in sync when changing any of these values.

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

- Code blocks: rounded 8 pt surface spanning the column; fences stay visible but faint.
- Quotes: a 3 pt accent bar, muted text, 16 pt indent.
- Lists: markers and task boxes in `listMarker` (text at 50%), matching the reader's muted `::marker`;
  wrapped lines hang under the item text.
- Focus mode dims everything but the current paragraph to 30 %; typewriter mode keeps the caret line centred.
