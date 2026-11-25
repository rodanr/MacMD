import Foundation
import Testing

@testable import MacMDKit

@Suite struct FootnoteTests {
    private func html(_ text: String) -> String { HTMLRenderer.render(text).body }

    // MARK: Definitions

    @Test func findsADefinition() throws {
        let text = "Text[^1].\n\n[^1]: The note."
        let definition = try #require(Footnotes.definitions(in: text).first)
        #expect(definition.label == "1")
        #expect(definition.content == "The note.")
        #expect(definition.line == 3)
        #expect((text as NSString).substring(with: definition.range) == "[^1]: The note.")
        #expect((text as NSString).substring(with: definition.labelRange) == "[^1]:")
    }

    @Test func indentedLinesContinueADefinition() throws {
        let text = "[^a]: one\n  two\nthree"
        let definition = try #require(Footnotes.definitions(in: text).first)
        #expect(definition.content == "one\ntwo")
        #expect((text as NSString).substring(with: definition.range) == "[^a]: one\n  two")
    }

    @Test func ignoresCodeAndFrontMatterAndKeepsTheFirstOfDuplicates() {
        #expect(Footnotes.definitions(in: "```\n[^1]: x\n```\n").isEmpty)
        #expect(Footnotes.definitions(in: "    [^1]: indented code\n").isEmpty)
        #expect(Footnotes.definitions(in: FrontMatter.fenced("---\n[^1]: x\n---\n")).isEmpty)
        #expect(Footnotes.definitions(in: "[^a]: first\n[^A]: second").map(\.content) == ["first"])
    }

    // MARK: Read mode

    @Test func rendersAReferenceAndTheNotesList() {
        #expect(
            html("Hi[^1].\n\n[^1]: Note **bold**.")
                == """
                <p data-line="1">Hi<sup class="footnote-ref"><a href="#fn:1" id="fnref:1">1</a></sup>.</p>
                <section class="footnotes">
                <ol>
                <li id="fn:1"><p>Note <strong>bold</strong>. <a href="#fnref:1" class="footnote-back" \
                aria-label="Back to reference 1">↩</a></p></li>
                </ol>
                </section>
                """)
    }

    @Test func numbersByFirstReferenceAndGivesRepeatsTheirOwnIDs() {
        let body = html("B[^b] A[^a] B[^b]\n\n[^a]: A\n[^b]: B")
        #expect(body.contains(##"<a href="#fn:1" id="fnref:1">1</a>"##))
        #expect(body.contains(##"<a href="#fn:2" id="fnref:2">2</a>"##))
        #expect(body.contains(##"<a href="#fn:1" id="fnref:1-2">1</a>"##))
        #expect(body.contains(#"<li id="fn:1"><p>B "#))
        #expect(body.contains(#"<li id="fn:2"><p>A "#))
    }

    @Test func labelsIgnoreCase() {
        #expect(html("x[^Note]\n\n[^note]: n").contains(##"<a href="#fn:1" id="fnref:1">1</a>"##))
    }

    @Test func aOneWordDefinitionIsNotALinkDefinition() {
        let body = html("See[^1]\n\n[^1]: Yes")
        #expect(body.contains(#"class="footnote-ref""#))
        #expect(!body.contains(#"href="Yes""#))
    }

    @Test func undefinedReferencesCodeAndLinksStayAsTheyAre() {
        #expect(html("x[^nope]") == #"<p data-line="1">x[^nope]</p>"#)
        #expect(html("`[^1]`\n\n[^1]: n").contains("<code>[^1]</code>"))
        #expect(html("[a [^1]](u)\n\n[^1]: n").contains(#"<a href="u">a [^1]</a>"#))
    }

    @Test func unreferencedDefinitionsAreStillListedWithoutABackLink() {
        let body = html("Text.\n\n[^lonely]: Still here.")
        #expect(body.contains(#"<li id="fn:1"><p>Still here.</p></li>"#))
        #expect(!body.contains("footnote-ref"))
    }

    @Test func footnotesCanHoldMathAndReferToEachOther() {
        let result = HTMLRenderer.render("a[^1]\n\n[^1]: See $x^2$ and[^2].\n[^2]: Second.")
        #expect(result.features.contains(.math))
        #expect(result.body.contains(##"<li id="fn:2"><p>Second. <a href="#fnref:2""##))
    }

    @Test func definitionsKeepLaterLineNumbers() {
        #expect(html("a[^1]\n[^1]: n\n\n# After").contains(#"<h1 id="after" data-line="4">After</h1>"#))
    }

    // MARK: Editor and outline

    @Test func editorStylesReferencesAndDefinitions() {
        let text = "Hi[^1].\n\n[^1]: Note"
        let spans = SpanCollector.spans(for: text)
        #expect(spans.substrings(of: .footnoteReference, in: text) == ["[^1]"])
        #expect(spans.substrings(of: .footnoteDefinition, in: text) == ["[^1]: Note"])
        #expect(spans.substrings(of: .syntaxMarker, in: text) == ["[^", "]", "[^1]:"])
    }

    @Test func editorLeavesUndefinedReferencesAlone() {
        let text = "x[^nope] and `[^1]`\n\n[^1]: n"
        #expect(SpanCollector.spans(for: text).substrings(of: .footnoteReference, in: text).isEmpty)
    }

    @Test func headingsDropReferencesFromTheOutlineAndAnchor() {
        let text = "# Intro[^1]\n\n[^1]: Yes"
        #expect(Outline.items(for: text).map(\.title) == ["Intro"])
        #expect(html(text).hasPrefix(#"<h1 id="intro" data-line="1">Intro<sup"#))
    }
}
