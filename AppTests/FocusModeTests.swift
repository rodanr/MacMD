import AppKit
import Testing

@testable import MacMD

/// An editor built like `EditorView` builds it, in an offscreen window, so geometry is real.
@MainActor
final class EditorHarness {
    let window: NSWindow
    let scrollView: NSScrollView
    let textView: MarkdownTextView
    let engine: StyleEngine
    let storage: NSTextStorage
    private let contentStorage: NSTextContentStorage

    init(text: String, size: NSSize = NSSize(width: 520, height: 420), fontSize: CGFloat = 16) async {
        storage = NSTextStorage(string: text)
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        contentStorage = NSTextContentStorage()
        contentStorage.textStorage = storage
        contentStorage.addTextLayoutManager(layoutManager)

        scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
        textView = MarkdownTextView(
            frame: NSRect(origin: .zero, size: scrollView.contentSize), textContainer: container)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxContentWidth = nil
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView

        let theme = Theme(id: .paper, fontSize: fontSize)
        engine = StyleEngine(storage: storage, textView: textView, theme: theme)
        textView.styleEngine = engine
        textView.focusShadeColor = theme.background
        textView.backgroundColor = theme.background
        window.makeFirstResponder(textView)
        await engine.settled()
        layout()
    }

    /// Runs the layout passes a visible window would run.
    func layout() {
        window.layoutIfNeeded()
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        window.displayIfNeeded()
    }

    func select(_ range: NSRange) async {
        textView.setSelectedRange(range)
        await engine.settled()
        layout()
    }

    func range(of needle: String) -> NSRange {
        let range = (storage.string as NSString).range(of: needle)
        precondition(range.location != NSNotFound, "\(needle) not in text")
        return range
    }

    /// The fraction of `range`'s text that is under a visible focus shade.
    func dimmedFraction(of needle: String) throws -> CGFloat {
        try dimmedFraction(of: range(of: needle))
    }

    func dimmedFraction(of range: NSRange) throws -> CGFloat {
        let rect = try #require(textView.rect(for: range)).insetBy(dx: 0, dy: 1)
        let shades = textView.subviews.compactMap { $0 as? FocusShadeView }.filter { !$0.isHidden }
        let covered = shades.reduce(CGFloat(0)) { total, shade in
            let overlap = shade.frame.intersection(rect)
            return total + (overlap.isNull ? 0 : overlap.width * overlap.height)
        }
        return rect.width * rect.height > 0 ? covered / (rect.width * rect.height) : 0
    }

    func expectReadable(_ needle: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let fraction = try dimmedFraction(of: needle)
        #expect(
            fraction == 0, "\(needle.prefix(30).debugDescription) is dimmed (\(fraction))",
            sourceLocation: sourceLocation)
    }

    func expectDimmed(_ needle: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let fraction = try dimmedFraction(of: needle)
        #expect(
            fraction > 0.95, "\(needle.prefix(30).debugDescription) is not dimmed (\(fraction))",
            sourceLocation: sourceLocation)
    }

    func close() { window.close() }
}

/// Focus mode keeps the paragraph being written at full strength and dims the rest.
@MainActor
@Suite struct FocusModeTests {
    static let wrapped =
        "Wrapped paragraph that is long enough to run over several lines in the column, so the focus has to cover all of them and not only the line with the caret on it."

    static let sample = """
        # Heading

        \(wrapped)

        - item one
        - item two

        Last paragraph.
        """

    private func editor(_ text: String = Self.sample) async -> EditorHarness {
        let editor = await EditorHarness(text: text)
        editor.textView.isFocusMode = true
        return editor
    }

    @Test func caretInAWrappedParagraphKeepsAllOfItReadable() async throws {
        let editor = await editor()
        defer { editor.close() }
        let paragraph = editor.range(of: Self.wrapped)
        #expect(try #require(editor.textView.rect(for: paragraph)).height > 40, "paragraph should wrap")
        await editor.select(NSRange(location: paragraph.location + 20, length: 0))
        try editor.expectReadable(Self.wrapped)
        try editor.expectDimmed("# Heading")
        try editor.expectDimmed("- item one")
        try editor.expectDimmed("Last paragraph.")
    }

    @Test func caretOnABlankLineKeepsTheParagraphAboveReadable() async throws {
        let editor = await editor()
        defer { editor.close() }
        let blank = NSMaxRange(editor.range(of: Self.wrapped)) + 1
        await editor.select(NSRange(location: blank, length: 0))
        try editor.expectReadable(Self.wrapped)
        try editor.expectDimmed("# Heading")
        try editor.expectDimmed("- item one")
    }

    @Test func blankLinesAtTheStartKeepTheFirstParagraphReadable() async throws {
        let editor = await editor("\n\nFirst words.\n\nSecond words.")
        defer { editor.close() }
        await editor.select(NSRange(location: 0, length: 0))
        try editor.expectReadable("First words.")
        try editor.expectDimmed("Second words.")
    }

    @Test func pressingReturnTwiceKeepsTheParagraphJustWrittenReadable() async throws {
        let editor = await editor("# Heading\n\n")
        defer { editor.close() }
        let end = editor.storage.length
        await editor.select(NSRange(location: end, length: 0))
        editor.textView.insertText("Just written.", replacementRange: editor.textView.selectedRange())
        await editor.engine.settled()
        editor.textView.insertNewline(nil)
        editor.textView.insertNewline(nil)
        await editor.engine.settled()
        editor.layout()
        try editor.expectReadable("Just written.")
        try editor.expectDimmed("# Heading")

        editor.textView.insertText("Next.", replacementRange: editor.textView.selectedRange())
        await editor.engine.settled()
        editor.layout()
        try editor.expectReadable("Next.")
        try editor.expectDimmed("Just written.")
    }

    /// Typing replaces the paragraph's layout fragment; the new one has no frame until it is laid out.
    @Test func typingInAParagraphKeepsItReadable() async throws {
        let editor = await editor()
        defer { editor.close() }
        await editor.select(NSRange(location: NSMaxRange(editor.range(of: "Last paragraph")), length: 0))
        for character in " grows" {
            editor.textView.insertText(String(character), replacementRange: editor.textView.selectedRange())
        }
        await editor.engine.settled()
        editor.layout()
        try editor.expectReadable("Last paragraph grows.")
        try editor.expectDimmed("- item two")
        try editor.expectDimmed("# Heading")
    }

    @Test func caretAfterTheFinalLineBreakKeepsTheLastParagraphReadable() async throws {
        let editor = await editor("First words.\n\nLast words.\n")
        defer { editor.close() }
        await editor.select(NSRange(location: editor.storage.length, length: 0))
        try editor.expectReadable("Last words.")
        try editor.expectDimmed("First words.")
    }

    @Test func listItemsAndHeadingsAreParagraphs() async throws {
        let editor = await editor()
        defer { editor.close() }
        await editor.select(NSRange(location: NSMaxRange(editor.range(of: "item two")) - 1, length: 0))
        try editor.expectReadable("- item two")
        try editor.expectDimmed("- item one")
        try editor.expectDimmed("Last paragraph.")

        await editor.select(NSRange(location: 3, length: 0))
        try editor.expectReadable("# Heading")
        try editor.expectDimmed(Self.wrapped)
    }

    @Test func aSelectionKeepsEveryParagraphItTouchesReadable() async throws {
        let editor = await editor()
        defer { editor.close() }
        let start = editor.range(of: Self.wrapped).location + 10
        let end = NSMaxRange(editor.range(of: "item one")) - 2
        await editor.select(NSRange(location: start, length: end - start))
        try editor.expectReadable(Self.wrapped)
        try editor.expectReadable("- item one")
        try editor.expectDimmed("# Heading")
        try editor.expectDimmed("- item two")
        try editor.expectDimmed("Last paragraph.")
    }

    @Test func dimmingFollowsAFontSizeChange() async throws {
        let editor = await editor()
        defer { editor.close() }
        await editor.select(NSRange(location: editor.range(of: "Last paragraph.").location + 2, length: 0))
        editor.engine.theme = Theme(id: .paper, fontSize: 26)
        await editor.engine.settled()
        editor.layout()
        try editor.expectReadable("Last paragraph.")
        try editor.expectDimmed("- item two")
        try editor.expectDimmed(Self.wrapped)
    }

    @Test func dimmingWorksWithVimMode() async throws {
        let editor = await editor()
        defer { editor.close() }
        editor.textView.isVimEnabled = true
        await editor.select(NSRange(location: editor.range(of: "item one").location + 2, length: 0))
        try editor.expectReadable("- item one")
        try editor.expectDimmed("- item two")
        try editor.expectDimmed(Self.wrapped)
    }

    static func longDocument(paragraphs: Int) -> String {
        (1...paragraphs).map { "Paragraph number \($0) of a long document, with a few more words on it." }
            .joined(separator: "\n\n")
    }

    /// TextKit 2 lays out lazily: far down a freshly opened document, fragments have only estimated frames.
    @Test func dimmingIsRightFarDownAFreshlyOpenedDocument() async throws {
        let editor = await editor(Self.longDocument(paragraphs: 400))
        defer { editor.close() }
        let target = editor.range(of: "Paragraph number 300 ")
        editor.textView.setSelectedRange(NSRange(location: target.location + 5, length: 0))
        editor.textView.scrollRangeToVisible(editor.textView.selectedRange())
        editor.layout()
        try editor.expectReadable("Paragraph number 300 ")
        try editor.expectDimmed("Paragraph number 299 ")
        try editor.expectDimmed("Paragraph number 301 ")
    }

    @Test func dimmingIsRightAtTheEndOfAFreshlyOpenedDocument() async throws {
        let editor = await editor(Self.longDocument(paragraphs: 400))
        defer { editor.close() }
        editor.textView.moveToEndOfDocument(nil)
        editor.layout()
        try editor.expectReadable("Paragraph number 400 ")
        try editor.expectDimmed("Paragraph number 399 ")
    }

    @Test func focusAndTypewriterTogether() async throws {
        let editor = await editor(Self.longDocument(paragraphs: 120))
        defer { editor.close() }
        editor.textView.isTypewriterMode = true
        await editor.select(NSRange(location: editor.range(of: "Paragraph number 80 ").location + 3, length: 0))
        try editor.expectReadable("Paragraph number 80 ")
        try editor.expectDimmed("Paragraph number 79 ")
        try editor.expectDimmed("Paragraph number 81 ")
    }

    /// Views don't clip to their bounds by default (macOS 14+), so a shade must not paint outside its frame,
    /// over the focused paragraph.
    @Test func shadesPaintOnlyTheirOwnFrame() throws {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let shade = FocusShadeView(frame: NSRect(x: 0, y: 60, width: 100, height: 40))
        shade.color = .black
        container.addSubview(shade)
        let bitmap = try #require(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: bitmap)
        // Bitmap rows run top down in pixels; the container is not flipped, so the shade covers the top 40 points.
        let scale = CGFloat(bitmap.pixelsHigh) / container.bounds.height
        let inside = try #require(bitmap.colorAt(x: 50, y: Int(20 * scale))).alphaComponent
        let outside = try #require(bitmap.colorAt(x: 50, y: Int(70 * scale))).alphaComponent
        #expect(inside > 0.3, "shade drawn: \(inside)")
        #expect(outside == 0, "nothing painted outside the shade: \(outside)")
    }

    /// Dimmed text keeps about 55 % of its strength: the shade is paper at about 45 % opacity.
    @Test func dimmedTextStaysReadable() throws {
        let shade = FocusShadeView(frame: NSRect(x: 0, y: 0, width: 4, height: 4))
        shade.color = .white
        let bitmap = try #require(shade.bitmapImageRepForCachingDisplay(in: shade.bounds))
        shade.cacheDisplay(in: shade.bounds, to: bitmap)
        let alpha = try #require(bitmap.colorAt(x: 2, y: 2)).alphaComponent
        #expect(abs(alpha - 0.45) < 0.03, "shade alpha \(alpha)")
    }
}

/// Typewriter mode keeps the caret line in the middle of the window.
@MainActor
@Suite struct TypewriterModeTests {
    private func caretOffset(_ editor: EditorHarness) throws -> CGFloat {
        let caret = try #require(
            editor.textView.rect(for: NSRange(location: editor.textView.selectedRange().location, length: 0)))
        return caret.midY - editor.scrollView.contentView.bounds.midY
    }

    @Test func caretStaysCenteredWhileMovingAndTyping() async throws {
        let text = FocusModeTests.longDocument(paragraphs: 120)
        let editor = await EditorHarness(text: text)
        defer { editor.close() }
        editor.textView.isTypewriterMode = true
        editor.layout()

        await editor.select(NSRange(location: editor.range(of: "Paragraph number 60 ").location + 4, length: 0))
        let offsetMoving = try caretOffset(editor)
        #expect(abs(offsetMoving) < 4, "after moving: \(offsetMoving)")

        editor.textView.insertText("typed ", replacementRange: editor.textView.selectedRange())
        editor.textView.insertNewline(nil)
        await editor.engine.settled()
        editor.layout()
        let offsetTyping = try caretOffset(editor)
        #expect(abs(offsetTyping) < 4, "after typing: \(offsetTyping)")

        // The last line can be centered too: the bottom inset makes room for it.
        editor.textView.moveToEndOfDocument(nil)
        await editor.engine.settled()
        editor.layout()
        let offsetEnd = try caretOffset(editor)
        #expect(abs(offsetEnd) < 4, "at the end: \(offsetEnd)")

        var expected = text as NSString
        let location = (text as NSString).range(of: "Paragraph number 60 ").location + 4
        expected =
            expected.replacingCharacters(in: NSRange(location: location, length: 0), with: "typed \n") as NSString
        #expect(editor.storage.string == expected as String)
    }

    @Test func nearTheTopTheDocumentIsNotScrolledPastItsStart() async throws {
        let editor = await EditorHarness(text: FocusModeTests.longDocument(paragraphs: 40))
        defer { editor.close() }
        editor.textView.isTypewriterMode = true
        await editor.select(NSRange(location: 3, length: 0))
        #expect(editor.scrollView.contentView.bounds.minY <= 0.5)
    }
}
