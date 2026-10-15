import Foundation
import Testing

@testable import MacMDKit

@Suite struct StandaloneHTMLTests {
    private let page = """
        <!doctype html>
        <html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src macmd://app">
        <link rel="stylesheet" href="macmd://app/reader.css">
        <link rel="stylesheet" href="macmd://app/vendor/highlight/github-dark.min.css" media="(prefers-color-scheme: dark)">
        <script src="macmd://app/reader.js"></script>
        </head><body><p>Hi</p><SCRIPT type="text/javascript">alert(1)</SCRIPT></body></html>
        """

    @Test func exportsCarryAStrictPolicyWithoutScripts() {
        let html = StandaloneHTML.make(from: page) { _ in "body{}" }
        #expect(html.contains(StandaloneHTML.contentSecurityPolicy))
        #expect(!html.contains("script-src macmd://app"))
        #expect(!html.lowercased().contains("<script"))
        #expect(StandaloneHTML.contentSecurityPolicy.contains("default-src 'none'"))
        #expect(!StandaloneHTML.contentSecurityPolicy.contains("script-src"))
        #expect(!StandaloneHTML.contentSecurityPolicy.contains("unsafe-eval"))
    }

    @Test func inlinesStylesheetsKeepingMediaQueries() {
        let html = StandaloneHTML.make(from: page) { path in path == "reader.css" ? "p{color:red}" : "pre{}" }
        #expect(html.contains("<style>\np{color:red}\n</style>"))
        #expect(html.contains(#"<style media="(prefers-color-scheme: dark)">"#))
        #expect(!html.contains("macmd://app/"))
    }

    @Test func addsThePolicyWhenThePageHasNone() {
        let html = StandaloneHTML.make(from: "<html><head></head><body></body></html>") { _ in nil }
        #expect(html.contains("<head>\n<meta http-equiv=\"Content-Security-Policy\""))
    }
}

@Suite struct SetextHeadingTests {
    @Test(arguments: ["Title\n-----\nnext", "Title\n=====\nnext para", "  Title\n---\nnext"])
    func headingEndsAtItsUnderline(text: String) {
        let spans = SpanCollector.spans(for: text)
        let headings = spans.filter { if case .heading = $0.kind { true } else { false } }
        #expect(headings.count == 1)
        let heading = (text as NSString).substring(with: headings[0].range)
        #expect(!heading.contains("next"), "heading styled \(heading.debugDescription)")
    }

    @Test func atxHeadingsAreUnchanged() {
        let text = "# Title\nnext"
        let headings = SpanCollector.spans(for: text).filter { if case .heading = $0.kind { true } else { false } }
        #expect((text as NSString).substring(with: headings[0].range) == "# Title")
    }
}
