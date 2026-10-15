import Foundation
import Testing

@testable import MacMDKit

/// Edge cases for the editing helpers behind ⌘B / ⌘I, Return in lists and ⌘1–⌘6.
@Suite struct EditingEdgeCaseTests {
    private func toggled(_ style: InlineFormatting.Style, _ marked: String) -> String {
        // `[` and `]` mark the selection.
        let start = (marked.components(separatedBy: "[")[0] as NSString).length
        let text = marked.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        let end = (marked.components(separatedBy: "]")[0].replacingOccurrences(of: "[", with: "") as NSString).length
        let edit = InlineFormatting.toggle(style, in: text, selection: NSRange(location: start, length: end - start))
        let result = NSMutableString(
            string: (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement))
        result.insert("]", at: NSMaxRange(edit.selection))
        result.insert("[", at: edit.selection.location)
        return result as String
    }

    @Test(arguments: [
        // Italic on a bold word adds italic; it must not turn bold into italic.
        (InlineFormatting.Style.emphasis, "**[bold]**", "***[bold]***"),
        (.emphasis, "[**bold**]", "[***bold***]"),
        // Removing italic from bold-italic keeps the bold.
        (.emphasis, "***[both]***", "**[both]**"),
        // Bold on an italic word adds bold.
        (.strong, "*[it]*", "***[it]***"),
        // Removing bold from bold-italic keeps the italic.
        (.strong, "***[both]***", "*[both]*"),
        (.strong, "[***both***]", "[*both*]"),
        // The basic cases still work.
        (.strong, "a [b] c", "a **[b]** c"),
        (.strong, "a **[b]** c", "a [b] c"),
        (.emphasis, "a *[b]* c", "a [b] c"),
        (.strikethrough, "~~[x]~~", "[x]"),
        (.inlineCode, "`[x]`", "[x]"),
    ])
    func boldAndItalicCombine(style: InlineFormatting.Style, before: String, after: String) {
        #expect(toggled(style, before) == after)
    }

    @Test(arguments: ["* * *", "- - -", "***", "---", "_ _ _", "  * * *"])
    func thematicBreaksAreNotLists(line: String) {
        #expect(ListContinuation.forLine(line) == .notAList)
    }

    @Test(arguments: [
        ("10. ten", ListContinuation.continue(prefix: "11. ")),
        ("> > deep", .continue(prefix: "> > ")),
        ("\t- tab", .continue(prefix: "\t- ")),
        ("+ plus", .continue(prefix: "+ ")),
        ("-no space", .notAList),
        ("1.no space", .notAList),
        ("😀 - not a list", .notAList),
    ])
    func moreContinuations(line: String, expected: ListContinuation) {
        #expect(ListContinuation.forLine(line) == expected)
    }

    @Test(arguments: [
        (1, "plain", "# plain"),
        (2, "# one", "## one"),
        (0, "### three", "three"),
        (3, "  ## indented", "### indented"),
        (1, "#hashtag", "# #hashtag"),
        (2, "####### seven", "## ####### seven"),
        (0, "", ""),
        (6, "", "###### "),
    ])
    func headings(level: Int, line: String, expected: String) {
        #expect(BlockFormatting.settingHeading(level: level, line: line) == expected)
    }

    @Test func slugsMatchGitHub() {
        var slugger = Slugger()
        #expect(slugger.slug("Hello World") == "hello-world")
        #expect(slugger.slug("Hello World") == "hello-world-1")
        #expect(slugger.slug("What's new?") == "whats-new")
        #expect(slugger.slug("Café & Crème") == "café--crème")
        #expect(slugger.slug("😀") == "section")
        #expect(slugger.slug("😀") == "section-1")
        #expect(slugger.slug("v1.2") == "v12")
        #expect(slugger.slug("snake_case-and-kebab") == "snake_case-and-kebab")
    }

    @Test func slugsStayUniqueWhenATitleLooksLikeADuplicate() {
        var slugger = Slugger()
        let slugs = ["Intro", "Intro 1", "Intro"].map { slugger.slug($0) }
        #expect(Set(slugs).count == slugs.count, "\(slugs)")
    }
}
