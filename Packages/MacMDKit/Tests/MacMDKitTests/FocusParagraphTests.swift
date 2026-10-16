import Foundation
import Testing

@testable import MacMDKit

@Suite struct FocusParagraphTests {
    private func focused(_ text: String, _ location: Int, _ length: Int = 0) -> String? {
        FocusParagraph.range(in: text as NSString, selection: NSRange(location: location, length: length))
            .map { (text as NSString).substring(with: $0) }
    }

    @Test func caretInAParagraphFocusesIt() {
        #expect(focused("a\n\nb", 0) == "a\n")
        #expect(focused("a\n\nb", 1) == "a\n")
        #expect(focused("a\n\nb", 3) == "b")
        #expect(focused("a\n\nb", 4) == "b")
    }

    @Test func blankLineFocusesTheParagraphAbove() {
        #expect(focused("a\n\nb", 2) == "a\n")
        #expect(focused("a\n\n\n\nb", 3) == "a\n")
        #expect(focused("a\n   \t\nb", 3) == "a\n")
    }

    @Test func blankLinesAtTheStartFocusTheParagraphBelow() {
        #expect(focused("\n\nb\n\nc", 0) == "b\n")
        #expect(focused("\n\nb\n\nc", 1) == "b\n")
    }

    @Test func caretAfterTheFinalLineBreakFocusesTheLastParagraph() {
        #expect(focused("a\n\nb\n", 5) == "b\n")
        #expect(focused("a\n\nb\n\n", 6) == "b\n")
    }

    @Test func selectionFocusesEveryLineItTouches() {
        #expect(focused("a\n\nb\n\nc", 0, 3) == "a\n\n")
        #expect(focused("a\n\nb\n\nc", 0, 4) == "a\n\nb\n")
        #expect(focused("a\n\nb\n\nc", 1, 5) == "a\n\nb\n\n")
        #expect(focused("a\n\nb\n\nc", 1, 6) == "a\n\nb\n\nc")
        // A selection of only blank lines behaves like a caret on them.
        #expect(focused("a\n\n\nb", 2, 1) == "a\n")
    }

    @Test func crlfLineBreaks() {
        #expect(focused("a\r\n\r\nb", 3) == "a\r\n")
        #expect(focused("a\r\n\r\nb", 5) == "b")
    }

    @Test func nothingToFocusInBlankText() {
        #expect(focused("", 0) == nil)
        #expect(focused("\n\n  \n", 2) == nil)
    }

    @Test func outOfRangeSelectionsAreClamped() {
        #expect(focused("a\n\nb", 99) == "b")
        #expect(focused("a\n\nb", 3, 99) == "b")
    }
}
