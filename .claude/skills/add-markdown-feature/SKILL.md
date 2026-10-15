---
name: add-markdown-feature
description: Use when adding or changing how a Markdown construct is styled in the editor or rendered in Read mode — new syntax (footnotes, ==highlight==, callouts, front matter), changed styling of headings, lists, code, math, tables, or a mismatch between editor and reader.
---

# Adding a Markdown feature

A construct is handled by two independent pipelines that must agree:

```
text ─┬─ SpanCollector → [StyleSpan(kind)] → MarkdownStyler → editor attributes
      └─ HTMLRenderer  → HTML + Features    → reader.css / reader.js → Read mode
```

Both parse with swift-markdown (cmark-gfm). **Syntax cmark doesn't know arrives as plain `Text` nodes.**

## Choose the approach for unknown syntax

| Syntax | Approach |
|---|---|
| Opaque content that must not be parsed as Markdown (math, raw blocks) | Pre-pass like `MathExtractor`: mask with same-**UTF-8**-length filler for spans; swap for private-use tokens for HTML (token helpers live in `Placeholder.swift`) |
| Inline formatting that nests with `**`, links … (`==mark==`, `^sup^`) | Pair delimiters inside the `Text` children of each inline container (paragraph, heading, table cell) with one shared helper used by both pipelines; get source ranges by scanning the source inside each `Text` node's mapped range (`Text.string` drops escapes) |

## Steps (test-first, REQUIRED: superpowers:test-driven-development)

1. **Tests** in `Packages/MacMDKit/Tests/MacMDKitTests/`: spans in `SpanCollectorTests` (`substrings(of:in:)`), HTML
   in `HTMLRendererTests`, samples in `RobustnessTests.samples` **and** new delimiter characters in the
   `randomInputNeverCrashes` alphabet. Add the construct to `Fixtures/kitchen-sink.md` — then update
   `kitchenSinkRendersEveryFeature`, which asserts the exact `Features` set and outline count.
2. **Spans**: new `StyleKind` case (`StyleSpan.swift`) — the compiler then flags every exhaustive switch to update.
   Emit it in `SpanWalker` (`SpanCollector.swift`); mark punctuation `.syntaxMarker`; ranges via `SourceRangeMapper`.
3. **Editor attributes**: handle the kind in the private `MarkdownStyler.apply(_:to:in:)` (not the public
   `apply(_:to:dirty:full:)`) and in `priority(_:)`. Inline looks use plain attributes (`.backgroundColor`, fonts via
   `addTraits`). Whole-paragraph backgrounds/bars use `BlockDecoration` + `DecoratedLayoutFragment` — never
   `NSTextBlock` (forces TextKit 1).
4. **HTML**: a `visit…` method in `HTMLVisitor` (`HTMLRenderer.swift`). Block elements keep `data-line`; inline ones
   don't need it. `visitText` must keep calling `Placeholder.replacing` so math still works.
   A JS library needs: a `RenderedHTML.Features` flag, `scripts/vendor-web-assets.sh`, injection in `ReaderPage.html`,
   rendering in `reader.js` before it posts `rendered`, and a CSP check.
5. **Headings**: if the syntax can appear in titles, strip it in `HeadingTitle.plainText` (`Outline.swift`) so the
   outline and anchors stay clean.
6. **Shortcut (inline styles)**: `InlineFormatting.Style` + marker, `MarkdownTextView.toggle…` action, item in `MainMenu.formatMenu()`.
7. **Style**: colors as tokens in `Theme.swift` and `reader.css` (light and dark), listed in `docs/DESIGN.md`.
8. Verify: `make test-kit`, then `make test-ui` and check the light and dark screenshots (`build-run-test` skill).

## Common mistakes

- Ranges from `String.count` or UTF-8 offsets → use `NSRange`/UTF-16 via `SourceRangeMapper`.
- Styling only the editor (or only the reader) → the modes disagree.
- Masking inline syntax like math → breaks nesting with emphasis and links.
