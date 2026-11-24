# MacMD logo

**Idea:** one mark that reads as both **M** (MacMD) and **#** (Markdown's heading sign). The M's two legs slant like
the uprights of a `#`, and two bars cross through them.

## Files

| File | Use |
|---|---|
| `macmd-symbol.svg` | Black, one colour: print, embossing, anywhere colour isn't available |
| `macmd-symbol-white.svg` | Reversed (paper white) for dark backgrounds |
| `macmd-symbol-color.svg` | Ink M and amber bars for light backgrounds |
| `macmd-app-icon.svg` | Flat app-icon artwork (no Liquid Glass) for places that need a plain image |
| `icon-layer-m.svg`, `icon-layer-hash.svg` | Sources for `App/Resources/AppIcon.icon/Assets/M.png` and `Hash.png` (1024 px) |

To change the app icon, edit the layer SVGs, export each one to a 1024 px transparent PNG, replace the files in
`AppIcon.icon/Assets/`, then run `make icon`. That refreshes `docs/screenshots/icon.png`; the website icons in `site/`
are resized from that file.

## Geometry

The symbol is drawn on a 256 grid with a 26-unit stroke, round caps and round joins.

- **Legs:** slanted at 75°.
- **Inner V of the M:** strokes at 75° and 120°.
- **Bars:** horizontal at y = 100 and y = 162. The lower bar is shifted left to follow the slant.

## Colour

| Token | HEX | Role |
|---|---|---|
| Ink | `#1F2228` | M on light backgrounds |
| Ink gradient | `#2E3138` → `#111318` | App icon background |
| Paper | `#F4F2EC` | M on dark backgrounds |
| Amber | `#F2A93B` | The heading bars (the `#`) |

## Usage

- **Clear space:** at least one bar thickness on every side.
- **Minimum size:** 16 px.
- **Don't:**
  - recolour the M amber;
  - swap the layer order (the M sits above the bars);
  - add outlines or effects outside the app icon's system glass.
