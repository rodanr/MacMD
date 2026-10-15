# MacMD 0.1 — design spec

**Date:** 2026-10-15 · **Status:** approved, implemented in v0.1.0

## Goal

A native, light, beautiful Markdown reader and editor for Apple silicon Macs, inspired by Typora, built to be
maintained with agentic coding.

## Decisions (confirmed with the maintainer)

| Topic | Decision |
|---|---|
| Editing model | Native TextKit 2 editor that styles Markdown as you type (syntax dimmed, not hidden), plus a rendered Read mode toggled with ⌘E |
| Platform | macOS 26 Tahoe or later, arm64 only |
| Distribution | Ad-hoc signed DMG on GitHub Releases; Developer ID signing and notarization switch on when secrets exist |
| 0.1 features | Outline and folder sidebar · focus and typewriter modes · code highlighting, tables, KaTeX math, Mermaid · HTML/PDF export, print · three themes |
| Extras | Status bar (words, reading time, caret), formatting shortcuts, list/quote/task continuation, Tab indent, wrap-selection-with-delimiter, image drag and paste, external-change reload, Copy as HTML, CLI file arguments |

## Non-goals for 0.1

Hiding syntax markers (Typora's WYSIWYG): too bug-prone in a source-preserving editor. Also out: plugins,
iCloud sync, Intel builds, App Store sandboxing.

## Quality targets

- Idle memory under 60 MB with the reader closed (measured: 48 MB)
- Restyle under 25 ms for a 60 KB document (measured: 22 ms in release)
- No timers or polling; nothing runs while idle

## Architecture

See [ARCHITECTURE.md](../../ARCHITECTURE.md). Key risks and their mitigations:

| Risk | Mitigation |
|---|---|
| UTF-8 vs UTF-16 offsets | `SourceRangeMapper`, with tests for emoji, CJK and CRLF |
| Stale async styling | Generation counter, and no styling during IME composition |
| Full re-layout on every keystroke | Block signatures plus a dirty range |
| TeX mangled by cmark | `MathExtractor` masking and placeholders |
| Scripts in Markdown files | CSP allowing scripts only from `macmd://app` |
