import Foundation
import Testing

@testable import MacMDKit

@Suite struct RobustnessTests {
    static let samples: [String] = [
        "", "\n", "#", "# ", "**", "`", "```", "```\n", "$", "$$", "$$$", "\\", "> ", "- ", "1.",
        "- [ ]", "| a |\n|", "[a](", "![](", "<div>", "\r\n\r\n", "~~~\n$x$\n~~~", "* * *",
        "a\u{0}b", "😀**😀**😀", "Title\n===", "  - a\n    - b\n      - c", "$x$\r\n$$\r\ny\r\n$$",
    ]

    @Test(arguments: samples)
    func edgeCasesProduceInBoundsSpans(text: String) {
        assertWellFormed(text)
    }

    @Test func randomInputNeverCrashes() {
        let alphabet = Array("ab #*_`~$\\>-+1.[]()!|:\n\r\t😀é漢<>&\"x")
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<500 {
            let length = Int.random(in: 0..<80, using: &generator)
            let text = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            assertWellFormed(text)
        }
    }

    @Test func kitchenSinkRendersEveryFeature() throws {
        let url = try #require(
            Bundle.module.url(forResource: "kitchen-sink", withExtension: "md", subdirectory: "Fixtures"))
        let text = try String(contentsOf: url, encoding: .utf8)
        assertWellFormed(text)
        let rendered = HTMLRenderer.render(text)
        #expect(rendered.features == [.code, .math, .mermaid])
        #expect(Outline.items(for: text).count == 6)
    }

    private func assertWellFormed(_ text: String) {
        let length = (text as NSString).length
        let result = SpanCollector.collect(text)
        for span in result.spans {
            #expect(span.range.location >= 0 && NSMaxRange(span.range) <= length, "\(span) in \(text.debugDescription)")
        }
        for block in result.blocks {
            #expect(NSMaxRange(block.range) <= length)
        }
        _ = HTMLRenderer.render(text)
        _ = Outline.items(for: text)
        _ = ListContinuation.forLine(text)
    }
}

/// Deterministic SplitMix64 generator so random tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
