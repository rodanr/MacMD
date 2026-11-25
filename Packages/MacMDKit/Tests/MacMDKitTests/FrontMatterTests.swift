import Foundation
import Testing

@testable import MacMDKit

@Suite struct FrontMatterTests {
    private func block(_ text: String) -> String? {
        FrontMatter.range(in: text).map { (text as NSString).substring(with: $0) }
    }

    // MARK: Detection

    @Test func detectsYAMLAtTheTop() {
        #expect(block("---\ntitle: Hi\ntags: [a, b]\n---\n# Body\n") == "---\ntitle: Hi\ntags: [a, b]\n---")
    }

    @Test func closesWithDotsAndToleratesTrailingSpaces() {
        #expect(block("---  \ntitle: Hi\n...\ntext") == "---  \ntitle: Hi\n...")
        #expect(block("---\ntitle: Hi\n---\t\n") == "---\ntitle: Hi\n---\t")
    }

    @Test func emptyFrontMatterAndFileEndingAtTheClosingLine() {
        #expect(block("---\n---\n") == "---\n---")
        #expect(block("---\na: 1\n---") == "---\na: 1\n---")
    }

    @Test func windowsLineEndings() {
        #expect(block("---\r\ntitle: Hi\r\n---\r\nBody") == "---\r\ntitle: Hi\r\n---")
    }

    @Test func onlyAtTheVeryStartOfTheFile() {
        #expect(block("\n---\na: 1\n---\n") == nil)
        #expect(block("Intro\n---\na: 1\n---\n") == nil)
        #expect(block(" ---\na: 1\n---\n") == nil)
    }

    @Test func needsExactlyThreeDashesAndAClosingLine() {
        #expect(block("----\na: 1\n----\n") == nil)
        #expect(block("--- x\na: 1\n---\n") == nil)
        #expect(block("---\na: 1\nno closing line\n") == nil)
        #expect(block("---") == nil)
        #expect(block("") == nil)
    }

    // MARK: Rewriting keeps positions

    @Test func fencedKeepsLengthAndLines() {
        let text = "---\ntitle: Hi 😀\n...\n# Body\n"
        let fenced = FrontMatter.fenced(text)
        #expect(fenced == "~~~\ntitle: Hi 😀\n~~~\n# Body\n")
        #expect(fenced.utf8.count == text.utf8.count)
        #expect(fenced.utf16.count == text.utf16.count)
        #expect(FrontMatter.fenced("# No front matter\n---\n") == "# No front matter\n---\n")
    }

    @Test func removedKeepsLineCount() {
        let text = "---\na: 1\nb: 2\n---\n# Body\n"
        let removed = FrontMatter.removed(text)
        #expect(removed == "\n\n\n\n# Body\n")
        #expect(FrontMatter.removed("plain\n") == "plain\n")
    }

    // MARK: Pipelines

    @Test func editorShowsItAsACodeBlockWithDimDelimiters() {
        let text = "---\ntitle: Hi\n---\n# Body\n"
        let spans = SpanCollector.spans(for: text)
        #expect(spans.substrings(of: .codeBlock(language: nil), in: text) == ["---\ntitle: Hi\n---"])
        #expect(spans.substrings(of: .syntaxMarker, in: text) == ["---", "---", "# "])
        #expect(spans.substrings(of: .thematicBreak, in: text).isEmpty)
        #expect(spans.substrings(of: .heading(level: 2), in: text).isEmpty)
        #expect(spans.substrings(of: .heading(level: 1), in: text) == ["# Body"])
    }

    @Test func dollarSignsInFrontMatterAreNotMath() {
        let text = "---\nprice: $5 and $6\n---\nBody\n"
        #expect(SpanCollector.spans(for: text).substrings(of: .math, in: text).isEmpty)
        #expect(!HTMLRenderer.render(text).features.contains(.math))
    }

    @Test func readModeHidesItAndKeepsLineNumbers() {
        let html = HTMLRenderer.render("---\ntitle: Hi\n---\n# Body\n").body
        #expect(html == #"<h1 id="body" data-line="4">Body</h1>"#)
    }

    @Test func outlineSkipsIt() {
        let outline = Outline.items(for: "---\ntitle: Hi\n---\n# Body\n")
        #expect(outline.map(\.title) == ["Body"])
        #expect(outline.map(\.line) == [4])
    }
}
