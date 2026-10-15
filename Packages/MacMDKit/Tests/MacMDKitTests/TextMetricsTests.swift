import Testing

@testable import MacMDKit

@Suite struct TextMetricsTests {
    @Test(arguments: [
        (0, 1), (1, 1), (2, 2), (3, 2), (4, 2), (5, 3), (6, 3),
    ])
    func lineNumbers(offset: Int, expected: Int) {
        #expect(TextMetrics.lineNumber(in: "a\nbc\nd", atUTF16Offset: offset) == expected)
    }

    @Test func crlfCountsOnce() {
        #expect(TextMetrics.lineNumber(in: "a\r\nb\rc", atUTF16Offset: 4) == 2)
        #expect(TextMetrics.lineNumber(in: "a\r\nb\rc", atUTF16Offset: 5) == 3)
    }

    @Test func clampsOutOfRange() {
        #expect(TextMetrics.lineNumber(in: "a\nb", atUTF16Offset: 99) == 2)
        #expect(TextMetrics.lineNumber(in: "", atUTF16Offset: 0) == 1)
    }
}
