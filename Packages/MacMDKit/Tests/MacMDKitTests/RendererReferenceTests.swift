import Foundation
import Testing
import cmark_gfm
import cmark_gfm_extensions

@testable import MacMDKit

/// Differential test: MacMD's HTML renderer against cmark-gfm's own, on random documents. MacMD adds
/// anchors, line numbers and classes, so the comparison is on visible text and the order of elements.
@Suite struct RendererReferenceTests {
    static func referenceHTML(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        // swift-markdown turns on smart punctuation ("quotes", -- dashes), so the reference does too.
        guard let parser = cmark_parser_new(CMARK_OPT_TABLE_SPANS | CMARK_OPT_SMART) else { return "" }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "tasklist"] {
            cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension(name))
        }
        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }
        guard let html = cmark_render_html(document, CMARK_OPT_UNSAFE | CMARK_OPT_SMART, cmark_parser_get_syntax_extensions(parser))
        else { return "" }
        defer { free(html) }
        return String(cString: html)
    }

    /// Element names in document order, without the ones only one side produces.
    static func elements(_ html: String) -> [String] {
        html.matches(of: /<([a-zA-Z][a-zA-Z0-9]*)/).map { String($0.output.1).lowercased() }
            .filter { !["input", "span", "div"].contains($0) }
    }

    /// Visible text with tags removed, entities decoded and white space collapsed.
    static func text(_ html: String) -> String {
        var text = html.replacing(/<[^>]*>/, with: " ")
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static let alphabet = Array("ab #*_`~\\>-+1.[]()!|:\n\n\n\t é漢<>&\"'xy=")

    static let lines = [
        "# Heading *one*", "## Two `code`", "Setext", "---", "===", "plain text with **bold** and _em_",
        "- item", "  - nested item", "    - deeper", "1. first", "2) second", "10. tenth", "- [ ] task", "- [x] done",
        "> quote", "> > nested quote", "> - quoted list", "| a | b |", "|---|:-:|", "| 1 | 2 |", "| x |",
        "```", "```swift", "~~~", "    indented code", "<div>", "</div>", "<!-- comment -->", "<b>inline</b> html",
        "[link](https://example.com \"title\")", "![image](a.png)", "<https://example.com>", "line with break  ",
        "backslash break\\", "&copy; &#35; &amp;", "*a **b** c*", "~~strike~~", "***", "", "", "text", "\\* not a list",
        "[ref]: https://example.com", "[ref]", "a | b", "\t- tabbed", "1.no", "+ plus", "* star",
    ]

    @Test(arguments: 0..<6)
    func structuredDocumentsMatchCmark(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 9500)
        var failures: [String] = []
        for _ in 0..<500 {
            let count = Int.random(in: 1...14, using: &generator)
            let markdown = (0..<count).map { _ in Self.lines.randomElement(using: &generator)! }.joined(separator: "\n")
            let ours = HTMLRenderer.render(markdown).body
            let reference = Self.referenceHTML(markdown)
            if Self.text(ours) != Self.text(reference) || Self.elements(ours) != Self.elements(reference) {
                failures.append(markdown)
            }
        }
        if let shortest = failures.min(by: { $0.count < $1.count }) {
            Issue.record(
                """
                \(failures.count) of 500 differ. Shortest: \(shortest.debugDescription)
                ours:      \(HTMLRenderer.render(shortest).body.debugDescription)
                reference: \(Self.referenceHTML(shortest).debugDescription)
                """)
        }
    }

    @Test(arguments: 0..<6)
    func rendererMatchesCmark(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 9000)
        var failures: [String] = []
        for _ in 0..<500 {
            let length = Int.random(in: 0...120, using: &generator)
            let markdown = String((0..<length).map { _ in Self.alphabet.randomElement(using: &generator)! })
            let ours = HTMLRenderer.render(markdown).body
            let reference = Self.referenceHTML(markdown)
            if Self.text(ours) != Self.text(reference) || Self.elements(ours) != Self.elements(reference) {
                failures.append(markdown)
            }
        }
        if let shortest = failures.min(by: { $0.count < $1.count }) {
            Issue.record(
                """
                \(failures.count) of 500 differ. Shortest: \(shortest.debugDescription)
                ours:      \(HTMLRenderer.render(shortest).body.debugDescription)
                reference: \(Self.referenceHTML(shortest).debugDescription)
                """)
        }
    }
}
