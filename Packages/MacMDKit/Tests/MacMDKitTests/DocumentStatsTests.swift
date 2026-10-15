import Testing

@testable import MacMDKit

@Suite struct DocumentStatsTests {
    @Test func countsWordsAndCharacters() {
        let stats = DocumentStats(text: "# Hello world\n\nThis is **MacMD**.")
        #expect(stats.words == 5)
        #expect(stats.characters == 33)
        #expect(stats.readingMinutes == 1)
    }

    @Test func emptyDocument() {
        let stats = DocumentStats(text: "")
        #expect(stats.words == 0)
        #expect(stats.readingMinutes == 0)
    }

    @Test func readingTimeRoundsUp() {
        let text = Array(repeating: "word", count: 460).joined(separator: " ")
        #expect(DocumentStats(text: text).readingMinutes == 2)
    }
}
