import Foundation
import Testing

@testable import MacMDKit

struct ReadingPositionTests {
    private func document(filler: Int = 0) -> String {
        let prefix = String(repeating: "intro\n\n", count: filler)
        let body = (1...30).map { "line \($0)\n" }.joined()
        return prefix + "# Alpha\n\n" + body + "\n# Beta\n\n" + body
    }

    @Test func makeFindsTheHeadingAboveTheLine() {
        let text = document()
        let outline = Outline.items(for: text)
        let beta = outline[1]
        let position = ReadingPosition.make(line: beta.line + 4, outline: outline, readMode: true)
        #expect(position.headingSlug == "beta")
        #expect(position.linesBelowHeading == 4)
        #expect(position.readMode)
    }

    @Test func reanchorsOnTheHeadingAfterLinesAreInsertedAbove() throws {
        let original = document()
        let outline = Outline.items(for: original)
        let position = ReadingPosition.make(line: outline[1].line + 5, outline: outline, readMode: false)

        let edited = "new line\n\nanother\n\n" + original
        let target = try #require(position.resolve(in: edited))
        let beta = try #require(Outline.items(for: edited).first { $0.slug == "beta" })
        #expect(target.line == beta.line + 5)
        #expect(target.headingTitle == "Beta")
    }

    @Test func clampsWhenTheFileWasTruncatedAndTheHeadingIsGone() {
        let position = ReadingPosition(line: 500, headingSlug: "gone", linesBelowHeading: 3, readMode: false)
        let text = (1...20).map { "line \($0)" }.joined(separator: "\n")
        #expect(position.resolve(in: text)?.line == 20)
    }

    @Test func positionsNearTheTopAreNotOffered() {
        let position = ReadingPosition(line: 2, headingSlug: nil, linesBelowHeading: 0, readMode: false)
        #expect(position.resolve(in: document()) == nil)
    }

    @Test func staysWithinTheHeadingsSectionWhenItShrank() throws {
        let text = "# A\n\nx\ny\n\n# B\n\nz\n"
        let position = ReadingPosition(line: 90, headingSlug: "a", linesBelowHeading: 80, readMode: false)
        let target = try #require(position.resolve(in: text))
        #expect(target.line == 5)
    }

    @Test func storeEvictsTheOldestBeyondCapacity() {
        var store = ReadingPositionStore()
        for index in 0..<(ReadingPositionStore.capacity + 5) {
            let position = ReadingPosition(
                line: 10, headingSlug: nil, linesBelowHeading: 0, readMode: false,
                savedAt: Date(timeIntervalSince1970: Double(index)))
            store.record(position, for: "/file\(index)")
        }
        #expect(store.count == ReadingPositionStore.capacity)
        #expect(store.position(for: "/file0") == nil)
        #expect(store.position(for: "/file\(ReadingPositionStore.capacity + 4)") != nil)
    }

    @Test func storeRoundTripsThroughCodable() throws {
        var store = ReadingPositionStore()
        store.record(
            ReadingPosition(line: 42, headingSlug: "alpha", linesBelowHeading: 3, readMode: true), for: "/a.md")
        let decoded = try JSONDecoder().decode(ReadingPositionStore.self, from: JSONEncoder().encode(store))
        #expect(decoded == store)
    }
}
