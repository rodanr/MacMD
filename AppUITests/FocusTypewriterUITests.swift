import XCTest

/// Focus and typewriter modes while writing, with screenshots of each step for visual review.
final class FocusTypewriterUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func open(_ text: String, appearance: String) throws -> (XCUIApplication, XCUIElement, XCUIElement) {
        let file = try temporaryFolder().appending(path: "writing.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let app = launch([file.path, "-appearance", appearance])
        let window = app.windows.firstMatch
        let editor = window.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        return (app, window, editor)
    }

    private func value(_ editor: XCUIElement) -> String { editor.value as? String ?? "" }

    @MainActor
    func testFocusModeWhileWriting() throws {
        let intro = """
            # Notes

            The first paragraph was written earlier and should be dimmed but still readable while you write below it.

            A second paragraph, also dimmed once the caret leaves it.
            """
        for appearance in ["light", "dark"] {
            let (app, window, editor) = try open(intro, appearance: appearance)
            app.menuBars.menuBarItems["View"].click()
            app.menuBars.menuItems["Focus Mode"].click()
            XCTAssertTrue(window.buttons["Focus"].waitForExistence(timeout: 3), "focus mode is on")

            editor.click()
            editor.typeKey(.downArrow, modifierFlags: .command)
            editor.typeKey(.enter, modifierFlags: [])
            editor.typeKey(.enter, modifierFlags: [])
            editor.typeText("Now I am writing a new paragraph, and it should be the clearest text on the page.")
            attach(window, "focus-\(appearance)-1-typing")
            editor.typeKey(.enter, modifierFlags: [])
            editor.typeKey(.enter, modifierFlags: [])
            attach(window, "focus-\(appearance)-2-blank-line")
            editor.typeText("And then the next one.")
            attach(window, "focus-\(appearance)-3-next-paragraph")

            XCTAssertTrue(value(editor).hasSuffix("on the page.\n\nAnd then the next one."), value(editor))
            app.terminate()
        }
    }

    @MainActor
    func testTypewriterModeKeepsTheCaretLineCentered() throws {
        let text = (1...80).map { "Line \($0): a paragraph of a long document." }.joined(separator: "\n\n")
        for appearance in ["light", "dark"] {
            let (app, window, editor) = try open(text, appearance: appearance)
            app.menuBars.menuBarItems["View"].click()
            app.menuBars.menuItems["Typewriter Mode"].click()
            XCTAssertTrue(window.buttons["Typewriter"].waitForExistence(timeout: 3), "typewriter mode is on")

            editor.click()
            editor.typeKey(.upArrow, modifierFlags: .command)
            for _ in 0..<40 { editor.typeKey(.downArrow, modifierFlags: []) }
            editor.typeText("Typed: ")
            attach(window, "typewriter-\(appearance)-1-middle")
            editor.typeKey(.downArrow, modifierFlags: .command)
            editor.typeKey(.enter, modifierFlags: [])
            editor.typeText("The end.")
            attach(window, "typewriter-\(appearance)-2-end")

            XCTAssertTrue(value(editor).hasSuffix("long document.\nThe end."), value(editor))
            app.terminate()
        }
    }

    @MainActor
    func testFocusAndTypewriterTogether() throws {
        let text = (1...60).map { "Paragraph \($0) of a long document, with a few words." }.joined(separator: "\n\n")
        let (app, window, editor) = try open(text, appearance: "light")
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Focus Mode"].click()
        app.menuBars.menuBarItems["View"].click()
        app.menuBars.menuItems["Typewriter Mode"].click()
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeKey(.enter, modifierFlags: [])
        editor.typeKey(.enter, modifierFlags: [])
        editor.typeText("Written with both modes on.")
        attach(window, "focus-typewriter-light")
        XCTAssertTrue(value(editor).hasSuffix("few words.\n\nWritten with both modes on."))
        app.terminate()
    }
}
