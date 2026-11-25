import Foundation
import Testing

@testable import MacMDKit

@Suite struct AlertTests {
    private func html(_ text: String) -> String { HTMLRenderer.render(text).body }

    // MARK: Editor spans

    @Test func noteSpansTheQuoteAndMarksTheTitle() {
        let text = "> [!NOTE]\n> Read this.\n"
        let spans = SpanCollector.spans(for: text)
        #expect(spans.substrings(of: .alert(.note), in: text) == ["> [!NOTE]\n> Read this."])
        #expect(spans.substrings(of: .alertTitle(.note), in: text) == ["[!NOTE]"])
        #expect(spans.substrings(of: .syntaxMarker, in: text) == ["> ", "> "])
    }

    @Test(arguments: [
        ("[!TIP]", AlertKind.tip), ("[!important]", .important), ("[!Warning]", .warning), ("[!CAUTION]  ", .caution),
    ])
    func everyKindAnyCase(marker: String, kind: AlertKind) {
        let text = "> \(marker)\n> body"
        #expect(SpanCollector.spans(for: text).substrings(of: .alert(kind), in: text).count == 1)
    }

    @Test(arguments: [
        "> [!NOTE] text on the same line", "> [!NOTES]\n> x", "> [NOTE]\n> x", "[!NOTE]\nnot a quote",
        "- > [!NOTE]\n  > in a list", "> > [!NOTE]\n> > nested",
    ])
    func notAnAlert(text: String) {
        let spans = SpanCollector.spans(for: text)
        #expect(!spans.contains { if case .alert = $0.kind { true } else { false } })
        #expect(!html(text).contains("alert"))
    }

    // MARK: Read mode

    @Test func rendersTitleAndBody() {
        #expect(
            html("> [!TIP]\n> Use **this**.")
                == """
                <blockquote class="alert alert-tip" data-line="1">
                <p class="alert-title">Tip</p>
                <p data-line="2">Use <strong>this</strong>.</p>
                </blockquote>
                """)
    }

    @Test func markerAloneShowsJustTheTitle() {
        #expect(
            html("> [!WARNING]")
                == """
                <blockquote class="alert alert-warning" data-line="1">
                <p class="alert-title">Warning</p>
                </blockquote>
                """)
    }

    @Test func laterParagraphsAndBlocksRenderNormally() {
        let body = html("> [!CAUTION]\n> one\n>\n> two\n> - item")
        #expect(body.hasPrefix(#"<blockquote class="alert alert-caution" data-line="1">"#))
        #expect(body.contains(#"<p data-line="2">one</p>"#))
        #expect(body.contains(#"<p data-line="4">two</p>"#))
        #expect(body.contains(#"<li data-line="5">item</li>"#))
        #expect(!body.contains("[!CAUTION]"))
    }

    @Test func titlesAreCapitalized() {
        #expect(AlertKind.allCases.map(\.title) == ["Note", "Tip", "Important", "Warning", "Caution"])
    }
}
