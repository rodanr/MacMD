import Foundation
import Testing

@testable import MacMDKit

@Suite struct InlineFormattingTests {
    private func apply(_ edit: TextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func wrapsSelection() {
        let text = "make bold here"
        let edit = InlineFormatting.toggle(.strong, in: text, selection: NSRange(location: 5, length: 4))
        #expect(apply(edit, to: text) == "make **bold** here")
        #expect(edit.selection == NSRange(location: 7, length: 4))
    }

    @Test func unwrapsWhenMarkersSurroundSelection() {
        let text = "make **bold** here"
        let edit = InlineFormatting.toggle(.strong, in: text, selection: NSRange(location: 7, length: 4))
        #expect(apply(edit, to: text) == "make bold here")
        #expect(edit.selection == NSRange(location: 5, length: 4))
    }

    @Test func unwrapsWhenSelectionIncludesMarkers() {
        let text = "make *it* here"
        let edit = InlineFormatting.toggle(.emphasis, in: text, selection: NSRange(location: 5, length: 4))
        #expect(apply(edit, to: text) == "make it here")
    }

    @Test func emptySelectionInsertsMarkersAroundCaret() {
        let text = "ab"
        let edit = InlineFormatting.toggle(.inlineCode, in: text, selection: NSRange(location: 1, length: 0))
        #expect(apply(edit, to: text) == "a``b")
        #expect(edit.selection == NSRange(location: 2, length: 0))
    }

    @Test func linkSelectsURLPlaceholder() {
        let text = "go home"
        let edit = InlineFormatting.link(in: text, selection: NSRange(location: 3, length: 4))
        #expect(apply(edit, to: text) == "go [home](url)")
        #expect(edit.selection == NSRange(location: 10, length: 3))
    }
}
