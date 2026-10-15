import Foundation
import Markdown
import Testing

@testable import MacMDKit

@Suite struct SourceRangeMapperTests {
    @Test func asciiLocationsMapToUTF16Offsets() {
        let mapper = SourceRangeMapper("ab\ncd\n")
        #expect(mapper.utf16Offset(line: 1, column: 1) == 0)
        #expect(mapper.utf16Offset(line: 2, column: 1) == 3)
        #expect(mapper.utf16Offset(line: 2, column: 3) == 5)
    }

    @Test func multiByteCharactersAreConverted() {
        // "é" is 2 UTF-8 bytes / 1 UTF-16 unit, "😀" is 4 bytes / 2 units, "漢" is 3 bytes / 1 unit.
        let mapper = SourceRangeMapper("é😀漢x")
        #expect(mapper.utf16Offset(line: 1, column: 3) == 1)
        #expect(mapper.utf16Offset(line: 1, column: 7) == 3)
        #expect(mapper.utf16Offset(line: 1, column: 10) == 4)
    }

    @Test func crlfAndCRLineEndingsAreLineBreaks() {
        let mapper = SourceRangeMapper("a\r\nb\rc")
        #expect(mapper.utf16Offset(line: 2, column: 1) == 3)
        #expect(mapper.utf16Offset(line: 3, column: 1) == 5)
    }

    @Test func outOfBoundsLocationsAreClamped() {
        let mapper = SourceRangeMapper("ab\ncd")
        #expect(mapper.utf16Offset(line: 1, column: 99) == 2)
        #expect(mapper.utf16Offset(line: 9, column: 1) == nil)
        #expect(mapper.utf16Offset(line: 0, column: 1) == nil)
    }

    @Test func parsedNodeRangeMatchesSubstring() throws {
        let text = "# Héllo 😀\n\nSome **bold** text"
        let document = Document(parsing: text)
        let mapper = SourceRangeMapper(text)
        let strong = try #require(document.child(through: [1, 1]))
        let range = try #require(mapper.nsRange(strong.range))
        #expect((text as NSString).substring(with: range) == "**bold**")
        let heading = try #require(document.child(at: 0))
        let headingRange = try #require(mapper.nsRange(heading.range))
        #expect((text as NSString).substring(with: headingRange) == "# Héllo 😀")
    }
}
