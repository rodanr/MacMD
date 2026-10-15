import Testing

@testable import MacMDKit

@Suite struct BlockFormattingTests {
    @Test(arguments: [
        (2, "Title", "## Title"),
        (1, "### Title", "# Title"),
        (0, "## Title", "Title"),
        (3, "", "### "),
        (2, "  - item", "## - item"),
    ])
    func settingHeading(level: Int, line: String, expected: String) {
        #expect(BlockFormatting.settingHeading(level: level, line: line) == expected)
    }
}
