import AppKit
import XCTest

/// Feature tests: each drives one feature the way a person does and checks the result in the
/// document, on disk or on the pasteboard.
final class FeatureUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Opens `text` as a document in a fresh folder and returns the app, the editor and the file.
    @MainActor
    private func open(_ text: String, name: String = "doc.md", arguments: [String] = []) throws
        -> (XCUIApplication, XCUIElement, URL)
    {
        let file = try temporaryFolder().appending(path: name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        let app = launch([file.path] + arguments)
        let editor = app.windows.firstMatch.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        return (app, editor, file)
    }

    private func value(_ editor: XCUIElement) -> String { editor.value as? String ?? "" }

    // MARK: Formatting

    @MainActor
    func testFormattingShortcutsAndUndo() throws {
        let (app, editor, _) = try open("word")
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("b", modifierFlags: .command)
        XCTAssertEqual(value(editor), "**word**")
        editor.typeKey("i", modifierFlags: .command)
        XCTAssertEqual(value(editor), "***word***", "italic on bold gives bold italic")
        editor.typeKey("z", modifierFlags: .command)
        editor.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(value(editor), "word", "undo restores the original")
        editor.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(value(editor), "**word**", "redo")
        editor.typeKey("z", modifierFlags: .command)

        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("k", modifierFlags: .command)
        XCTAssertEqual(value(editor), "[word](url)")
        editor.typeText("https://example.com")
        XCTAssertEqual(value(editor), "[word](https://example.com)", "⌘K selects the URL placeholder")

        editor.typeKey("2", modifierFlags: .command)
        XCTAssertEqual(value(editor), "## [word](https://example.com)")
        editor.typeKey("0", modifierFlags: [.command, .option])
        XCTAssertEqual(value(editor), "[word](https://example.com)", "⌥⌘0 makes it a paragraph again")
        app.terminate()
    }

    @MainActor
    func testTypingADelimiterWrapsTheSelection() throws {
        let (app, editor, _) = try open("make this bold")
        editor.click()
        editor.typeKey(.leftArrow, modifierFlags: .command)
        for _ in 0..<5 { editor.typeKey(.rightArrow, modifierFlags: []) }
        for _ in 0..<4 { editor.typeKey(.rightArrow, modifierFlags: .shift) }
        editor.typeText("*")
        XCTAssertEqual(value(editor), "make *this* bold")
        editor.typeText("*")
        XCTAssertEqual(value(editor), "make **this** bold", "typing again wraps again")
        app.terminate()
    }

    @MainActor
    func testTabIndentsAndShiftTabOutdentsListItems() throws {
        let (app, editor, _) = try open("- one\n- two")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(value(editor), "- one\n    - two")
        editor.typeKey(.tab, modifierFlags: .shift)
        XCTAssertEqual(value(editor), "- one\n- two")
        app.terminate()
    }

    // MARK: Find

    @MainActor
    func testFindAndReplaceAll() throws {
        let (app, editor, _) = try open("one two one three one")
        editor.click()
        editor.typeKey("f", modifierFlags: [.command, .option])
        let window = app.windows.firstMatch
        let findField = window.searchFields.firstMatch
        XCTAssertTrue(findField.waitForExistence(timeout: 5), "the find bar opens")
        // macOS focuses Replace on ⌥⌘F; click Find, as a person would, and replace any earlier search.
        findField.click()
        findField.typeKey("a", modifierFlags: .command)
        findField.typeText("one")
        let replaceField = window.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Replace"))
            .firstMatch
        replaceField.click()
        replaceField.typeKey("a", modifierFlags: .command)
        replaceField.typeText("1")
        window.buttons["All"].click()
        XCTAssertTrue(waitUntil { self.value(editor) == "1 two 1 three 1" }, "got \(value(editor))")
        editor.click()  // focus was in the find bar, where ⌘Z undoes typing in the field
        editor.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            waitUntil { self.value(editor) == "one two one three one" },
            "Replace All undoes in one step, got \(value(editor))")
        app.terminate()
    }

    // MARK: Files

    @MainActor
    func testSaveWritesToDisk() throws {
        let (app, editor, file) = try open("start")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText(" and more")
        editor.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(
            waitUntil(timeout: 10) { (try? String(contentsOf: file, encoding: .utf8)) == "start and more" },
            "⌘S writes the file")
        app.terminate()
    }

    @MainActor
    func testReloadsWhenAnotherAppChangesTheFile() throws {
        let (app, editor, file) = try open("original")
        try "changed outside".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(waitUntil(timeout: 10) { self.value(editor) == "changed outside" }, "got \(value(editor))")
        app.terminate()
    }

    @MainActor
    func testKeepsTheFilesEncodingWhenSaving() throws {
        let folder = try temporaryFolder()
        let file = folder.appending(path: "latin1.md")
        try XCTUnwrap("café crème".data(using: .isoLatin1)).write(to: file)
        let app = launch([file.path])
        let editor = app.windows.firstMatch.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(value(editor), "café crème", "Latin-1 is decoded")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("!")
        editor.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: file)) == "café crème!".data(using: .isoLatin1) })
        app.terminate()
    }

    @MainActor
    func testNewDocumentCanBeSaved() throws {
        let folder = try temporaryFolder()
        let app = launch([])
        let editor = app.windows.firstMatch.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "an untitled document opens at launch")
        editor.click()
        editor.typeText("# Fresh")
        editor.typeKey("s", modifierFlags: .command)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path + "\n")
        let nameField = sheet.textFields.firstMatch
        nameField.doubleClick()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("fresh\n")
        let saved = folder.appending(path: "fresh.md")
        XCTAssertTrue(
            waitUntil(timeout: 10) { (try? String(contentsOf: saved, encoding: .utf8)) == "# Fresh" },
            "saved as fresh.md with a .md extension")
        app.terminate()
    }

    @MainActor
    func testLargeDocumentOpensWithPlainStylingAndStaysEditable() throws {
        let line = "Some **bold** text and `code` with [a link](https://example.com) in a long document.\n"
        let text = String(repeating: line, count: 2_200_000 / line.utf16.count + 1)
        let (app, editor, _) = try open(text)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.staticTexts["Large file — live styling paused"].waitForExistence(timeout: 15))
        editor.click()
        editor.typeKey(.upArrow, modifierFlags: .command)
        editor.typeText("Hello ")
        XCTAssertTrue(waitUntil(timeout: 10) { self.value(editor).hasPrefix("Hello Some") })
        app.terminate()
    }

    // MARK: Outline and Read mode

    @MainActor
    func testOutlineJumpsToHeadingsInBothModes() throws {
        let app = launch([fixture])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
        app.typeKey("1", modifierFlags: [.command, .control])
        window.buttons["Math"].click()
        let mathLine = try lineNumber(of: "## Math", in: fixture)
        XCTAssertTrue(
            window.staticTexts["Ln \(mathLine), Col 1"].waitForExistence(timeout: 5),
            "the caret moves to the Math heading")

        app.typeKey("e", modifierFlags: .command)
        let reader = window.webViews.firstMatch
        XCTAssertTrue(reader.staticTexts["Welcome to MacMD"].waitForExistence(timeout: 10))
        window.buttons["Diagrams"].click()
        let heading = reader.staticTexts["Diagrams"].firstMatch
        XCTAssertTrue(waitUntil { heading.exists && window.frame.contains(heading.frame) }, "Read mode scrolls to it")
        app.terminate()
    }

    @MainActor
    func testReadModeKeepsTheScrollPosition() throws {
        let app = launch([fixture])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
        app.typeKey("1", modifierFlags: [.command, .control])
        window.buttons["Diagrams"].click()
        app.typeKey("e", modifierFlags: .command)
        let heading = window.webViews.firstMatch.staticTexts["Diagrams"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { window.frame.contains(heading.frame) }, "Read mode opens where the editor was")
        app.terminate()
    }

    // MARK: Clipboard, printing, updates

    @MainActor
    func testCopyAsHTML() throws {
        let (app, editor, _) = try open("# Title\n\nSome **bold** text.")
        editor.click()
        NSPasteboard.general.clearContents()
        app.typeKey("c", modifierFlags: [.command, .option, .shift])
        XCTAssertTrue(
            waitUntil { NSPasteboard.general.string(forType: .html)?.contains("<strong>bold</strong>") == true })
        XCTAssertTrue(NSPasteboard.general.string(forType: .html)?.contains("<h1") == true)
        app.terminate()
    }

    @MainActor
    func testPrintPanelOpensAndCancels() throws {
        let (app, editor, _) = try open("# Print me")
        editor.click()
        app.typeKey("p", modifierFlags: .command)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "the print panel appears")
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil { !sheet.exists })
        XCTAssertTrue(editor.exists, "the document is still open and usable")
        dismissLocalNetworkPrompt(wait: 5)
        app.terminate()
    }

    @MainActor
    func testCheckForUpdatesAnswers() throws {
        // A local feed instead of GitHub: deterministic, and UI tests never touch the network.
        let folder = try temporaryFolder()
        for (tag, answer, button) in [
            ("v0.0.1", "You’re up to date", "OK"), ("v999.0.0", "MacMD 999.0.0 is available", "Later"),
        ] {
            let feed = folder.appending(path: "\(tag).json")
            try #"{"tag_name": "\#(tag)", "html_url": "https://github.com/rodanr/MacMD/releases"}"#.write(
                to: feed, atomically: true, encoding: .utf8)
            let app = launch(["-updateFeedURL", feed.absoluteString])
            app.menuBars.menuBarItems["MacMD"].click()
            app.menuBars.menuItems["Check for Updates…"].click()
            XCTAssertTrue(app.staticTexts[answer].waitForExistence(timeout: 10), "\(tag): \(answer)")
            app.buttons[button].firstMatch.click()
            app.terminate()
        }
    }

    private func lineNumber(of line: String, in path: String) throws -> Int {
        let lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: "\n")
        return try XCTUnwrap(lines.firstIndex(of: line)) + 1
    }
}
