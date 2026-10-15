import Foundation
import Testing

@testable import MacMDKit

@Suite struct MathExtractorTests {
    private func tex(_ text: String) -> [String] { MathExtractor.spans(in: text).map(\.tex) }

    @Test func inlineAndDisplayMath() {
        let spans = MathExtractor.spans(in: "a $x^2$ b\n\n$$\n\\frac{1}{2}\n$$\n")
        #expect(spans.map(\.tex) == ["x^2", "\n\\frac{1}{2}\n"])
        #expect(spans.map(\.isDisplay) == [false, true])
    }

    @Test func currencyIsNotMath() {
        #expect(tex("costs $5 and $10 today").isEmpty)
        #expect(tex("price $ 5 $ here").isEmpty)
    }

    @Test func escapedDollarIsIgnored() {
        #expect(tex("a \\$x$ b").isEmpty)
    }

    @Test func mathInsideCodeIsIgnored() {
        #expect(tex("`$x$` and\n```\n$y$\n```\n$z$").map { $0 } == ["z"])
    }

    @Test func maskingPreservesUTF8Length() {
        let text = "é $α_β$ z"
        let masked = MathExtractor.masked(text, spans: MathExtractor.spans(in: text))
        #expect(masked.utf8.count == text.utf8.count)
        #expect(!masked.contains("_"))
    }

    @Test func placeholdersRoundTrip() {
        let text = "a $x_1$ b"
        let (replaced, table) = MathExtractor.replacingWithPlaceholders(text)
        #expect(!replaced.contains("$"))
        #expect(table.count == 1)
        #expect(table.values.first?.tex == "x_1")
    }
}
