import Foundation
import Testing

@testable import MacMDKit

@Suite struct SpanCollectorTests {
    private func spans(_ text: String) -> [StyleSpan] { SpanCollector.spans(for: text) }

    @Test func headingSpanAndMarker() {
        let text = "## Title\n"
        let result = spans(text)
        #expect(result.substrings(of: .heading(level: 2), in: text) == ["## Title"])
        #expect(result.substrings(of: .syntaxMarker, in: text) == ["## "])
    }

    @Test func strongEmphasisAndStrikethroughMarkers() {
        let text = "a **b** _c_ ~~d~~"
        let result = spans(text)
        #expect(result.substrings(of: .strong, in: text) == ["**b**"])
        #expect(result.substrings(of: .emphasis, in: text) == ["_c_"])
        #expect(result.substrings(of: .strikethrough, in: text) == ["~~d~~"])
        #expect(result.substrings(of: .syntaxMarker, in: text) == ["**", "**", "_", "_", "~~", "~~"])
    }

    @Test func inlineCodeMarksBackticks() {
        let text = "use ``a`b`` now"
        let result = spans(text)
        #expect(result.substrings(of: .inlineCode, in: text) == ["``a`b``"])
        #expect(result.substrings(of: .syntaxMarker, in: text) == ["``", "``"])
    }

    @Test func fencedCodeBlockMarksFences() {
        let text = "```swift\nlet x = 1\n```\n"
        let result = spans(text)
        #expect(result.substrings(of: .codeBlock(language: "swift"), in: text) == ["```swift\nlet x = 1\n```"])
        #expect(result.substrings(of: .syntaxMarker, in: text) == ["```swift", "```"])
    }

    @Test func linkMarksBracketsAndDestination() {
        let text = "see [docs](https://x.y) ok"
        let result = spans(text)
        #expect(result.substrings(of: .link, in: text) == ["[docs](https://x.y)"])
        #expect(result.substrings(of: .syntaxMarker, in: text) == ["[", "](https://x.y)"])
    }

    @Test func listMarkersAndTaskBoxes() {
        let text = "- one\n- [x] done\n1. first\n"
        let result = spans(text)
        #expect(result.substrings(of: .listMarker, in: text) == ["- ", "- ", "1. "])
        #expect(result.substrings(of: .taskBox(checked: true), in: text) == ["[x]"])
    }

    @Test func blockQuoteMarkers() {
        let text = "> a\n> b\n"
        let result = spans(text)
        #expect(result.substrings(of: .blockQuote, in: text) == ["> a\n> b"])
        #expect(result.substrings(of: .syntaxMarker, in: text) == ["> ", "> "])
    }

    @Test func mathIsNotParsedAsEmphasis() {
        let text = "x $a_b_c$ y"
        let result = spans(text)
        #expect(result.substrings(of: .emphasis, in: text).isEmpty)
        #expect(result.substrings(of: .math, in: text) == ["$a_b_c$"])
    }

    @Test func unicodeRangesStayAligned() {
        let text = "# 😀 é\n\n漢字 **太字**"
        let result = spans(text)
        #expect(result.substrings(of: .strong, in: text) == ["**太字**"])
        #expect(result.substrings(of: .heading(level: 1), in: text) == ["# 😀 é"])
    }

    @Test func thematicBreakAndTable() {
        let text = "---\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        let result = spans(text)
        #expect(result.substrings(of: .thematicBreak, in: text) == ["---"])
        #expect(result.substrings(of: .table, in: text).count == 1)
    }

    @Test func blocksPartitionTopLevelNodes() {
        let text = "# A\n\npara\n\n- x\n"
        let blocks = SpanCollector.collect(text).blocks
        #expect(blocks.count == 3)
        #expect(blocks.map(\.range.location) == [0, 5, 11])
    }
}
