---
name: add-theme
description: Use when adding a new visual theme to MacMD or changing theme fonts, colors or spacing so the editor and Read mode stay consistent.
---

# Adding or changing a theme

A theme exists in three places that must match (token list in `docs/DESIGN.md`):

| Place | What to change |
|---|---|
| `App/Theme/Theme.swift` | `Theme.ID` case + `displayName`/`summary`; font design in `font(size:weight:)`; `background`/`text` colors (light + dark hex) |
| `App/Resources/Web/reader.css` | `html[data-theme="<id>"]` block with `--font-body`, `--size`, `--leading`, `--paper`, `--ink*`, `--surface`, plus a `prefers-color-scheme: dark` override |
| Menus/settings | Automatic — `Theme.ID.allCases` drives the View ▸ Theme menu, the toolbar menu and Settings |

## Rules

- Use system fonts only (`.serif` = New York, `.default` = SF Pro, `.monospaced` = SF Mono); no bundled web fonts.
- Accent comes from the user's macOS accent color (`.controlAccentColor` / CSS `AccentColor`) — don't hard-code one.
- Check contrast: body text ≥ 7:1 on the background, muted text ≥ 4.5:1.
- Verify with `make test-ui` screenshots after adding `-theme <id>` to the launch arguments in `MacMDUITests`.
