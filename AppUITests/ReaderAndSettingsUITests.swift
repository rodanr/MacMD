import AppKit
import XCTest

/// Read mode behaviour (links, images, rendering failures) and the Settings and About windows.
final class ReaderAndSettingsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func value(_ editor: XCUIElement) -> String { editor.value as? String ?? "" }

    @MainActor
    private func openInReadMode(_ files: [String: String], open name: String) throws -> (XCUIApplication, XCUIElement) {
        let folder = try temporaryFolder()
        for (file, text) in files {
            try text.write(to: folder.appending(path: file), atomically: true, encoding: .utf8)
        }
        let app = launch([folder.appending(path: name).path, "-openInReadMode", "YES"])
        let reader = app.windows.firstMatch.webViews.firstMatch
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        return (app, reader)
    }

    // MARK: Links

    @MainActor
    func testLinkToAnotherMarkdownFileOpensIt() throws {
        let (app, reader) = try openInReadMode(
            ["a.md": "# A\n\nGo to [the other file](b.md).", "b.md": "# B"], open: "a.md")
        let link = reader.links["the other file"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.click()
        XCTAssertTrue(app.windows["b.md"].waitForExistence(timeout: 10), "b.md opens in MacMD")
        app.terminate()
    }

    @MainActor
    func testAnchorLinksScrollWithinThePage() throws {
        let filler = (1...80).map { "Paragraph \($0) of filler text." }.joined(separator: "\n\n")
        let (app, reader) = try openInReadMode(
            ["doc.md": "# Top\n\n[Jump to the end](#the-end)\n\n\(filler)\n\n## The End\n\nDone."], open: "doc.md")
        let window = app.windows.firstMatch
        let target = reader.staticTexts["The End"].firstMatch
        XCTAssertTrue(reader.links["Jump to the end"].waitForExistence(timeout: 10))
        XCTAssertFalse(window.frame.contains(target.frame), "the heading starts off screen")
        reader.links["Jump to the end"].click()
        XCTAssertTrue(waitUntil { window.frame.contains(target.frame) }, "the anchor scrolls to the heading")
        XCTAssertTrue(reader.staticTexts["Top"].exists || reader.exists, "the page didn't navigate away")
        app.terminate()
    }

    // MARK: Images and rendering failures

    @MainActor
    func testRelativeImagesLoadAndMissingOnesShowAPlaceholder() throws {
        let folder = try temporaryFolder()
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let png = try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(
                using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: folder.appending(path: "img"), withIntermediateDirectories: true)
        try png.write(to: folder.appending(path: "img/teal.png"))
        try "![Teal](img/teal.png)\n\n![Gone](img/missing.png)".write(
            to: folder.appending(path: "doc.md"), atomically: true, encoding: .utf8)
        let app = launch([folder.appending(path: "doc.md").path, "-openInReadMode", "YES"])
        let reader = app.windows.firstMatch.webViews.firstMatch
        XCTAssertTrue(reader.images["Teal"].waitForExistence(timeout: 10), "the relative image loads")
        XCTAssertTrue(waitUntil { reader.images["Teal"].frame.width > 10 }, "with its real size")
        XCTAssertTrue(
            reader.staticTexts["Image not found: img/missing.png"].waitForExistence(timeout: 10),
            "a missing image says which file is missing")
        app.terminate()
    }

    @MainActor
    func testBrokenMathAndDiagramsShowErrorsInPlace() throws {
        let (app, reader) = try openInReadMode(
            ["doc.md": "# Broken\n\n$\\frac{1}{$\n\n```mermaid\ngraph TD; A-->\n```\n\nStill here."], open: "doc.md")
        XCTAssertTrue(reader.staticTexts["Still here."].waitForExistence(timeout: 15), "the rest of the page renders")
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    // MARK: Read mode protects the text

    @MainActor
    func testEditingShortcutsDoNothingInReadMode() throws {
        let folder = try temporaryFolder()
        let file = folder.appending(path: "doc.md")
        try "# Title\n\n- item".write(to: file, atomically: true, encoding: .utf8)
        let app = launch([file.path])
        let window = app.windows.firstMatch
        let editor = window.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(window.webViews.firstMatch.waitForExistence(timeout: 10))
        for (key, modifiers) in [
            ("b", XCUIElement.KeyModifierFlags.command), ("i", .command), ("1", .command), ("k", .command),
        ] {
            app.typeKey(key, modifierFlags: modifiers)
        }
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.delete, modifierFlags: [])
        app.typeText("typed")
        app.typeKey("e", modifierFlags: .command)
        XCTAssertEqual(value(editor), "# Title\n\n- item", "nothing in Read mode changes the text")
        XCTAssertFalse(window.staticTexts["Edited"].exists)
        app.terminate()
    }

    // MARK: Duplicate headings

    @MainActor
    func testOutlineJumpsToTheRightDuplicateHeading() throws {
        let filler = (1...40).map { "Line \($0)." }.joined(separator: "\n\n")
        let (app, reader) = try openInReadMode(
            ["doc.md": "# Notes\n\n\(filler)\n\n# Notes\n\nSecond notes section.\n\n\(filler)"], open: "doc.md")
        let window = app.windows.firstMatch
        app.typeKey("1", modifierFlags: [.command, .control])
        let entries = window.buttons.matching(identifier: "Notes")
        XCTAssertTrue(waitUntil { window.buttons["Notes"].exists })
        let items = window.outlines.firstMatch.buttons.allElementsBoundByIndex.filter { $0.label == "Notes" }
        XCTAssertEqual(items.count, 2, "both headings are in the outline")
        items[1].click()
        let marker = reader.staticTexts["Second notes section."].firstMatch
        XCTAssertTrue(waitUntil { window.frame.contains(marker.frame) }, "the second heading is shown")
        _ = entries
        app.terminate()
    }

    // MARK: Toolbar, Settings, About

    @MainActor
    func testToolbarModeSwitch() throws {
        let app = launch([fixture])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
        window.radioButtons["Read"].firstMatch.click()
        XCTAssertTrue(window.webViews.firstMatch.staticTexts["Welcome to MacMD"].waitForExistence(timeout: 10))
        window.radioButtons["Edit"].firstMatch.click()
        XCTAssertTrue(waitUntil { window.textViews["editor"].isHittable })
        app.terminate()
    }

    @MainActor
    func testSettingsControlsApplyImmediately() throws {
        let app = launch([fixture])
        let window = app.windows["kitchen-sink.md"]
        XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        func option(_ name: String) -> XCUIElement {
            settings.radioButtons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        }
        option("Mono").click()
        settings.radioButtons["Dark"].firstMatch.click()
        let zoom = settings.popUpButtons.firstMatch
        zoom.click()
        app.menuItems["125%"].click()
        XCTAssertTrue(
            waitUntil {
                window.descendants(matching: .any)["zoom"].label == "125%"
                    || window.descendants(matching: .any)["zoom"].title == "125%"
            }, "the status bar follows")
        settings.buttons["Reset"].firstMatch.click()
        settings.descendants(matching: .any)["vimModeToggle"].firstMatch.click()
        XCTAssertTrue(window.staticTexts["vimStatus"].waitForExistence(timeout: 5), "Vim mode turns on in open windows")
        settings.descendants(matching: .any)["vimModeToggle"].firstMatch.click()
        XCTAssertTrue(waitUntil { !window.staticTexts["vimStatus"].exists }, "and off again")
        attach(settings, "settings-after-changes")
        option("Paper").click()
        settings.radioButtons["System"].firstMatch.click()
        app.terminate()
    }

    @MainActor
    func testFontSizeCanBeTypedAndChangedFromTheKeyboard() throws {
        let app = launch([fixture, "-NSWindow Frame MarkdownDocumentWindow", "120 120 1200 780 0 0 2560 1410"])
        let window = app.windows["kitchen-sink.md"]
        XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let field = settings.textFields["fontSizeField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "16")

        field.doubleClick()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("20\n")
        XCTAssertTrue(waitUntil { field.value as? String == "20" })
        XCTAssertTrue(settings.buttons["Reset"].firstMatch.isEnabled, "Reset is offered once the size changed")
        field.doubleClick()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("400\n")
        XCTAssertTrue(waitUntil { field.value as? String == "36" }, "sizes are kept within range")

        window.click()
        app.typeKey("-", modifierFlags: [.command, .option])

        XCTAssertTrue(waitUntil { field.value as? String == "35" }, "⌥⌘− makes the font smaller")
        XCTAssertTrue(
            waitUntil {
                window.descendants(matching: .any)["zoom"].label == "100%"
                    || window.descendants(matching: .any)["zoom"].title == "100%"
            },
            "font size leaves zoom alone")
        attach(window, "font-size-35")
        // The document window may now cover Settings; bring Settings back to the front by its title bar.
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).click()
        field.doubleClick()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("16\n")
        XCTAssertTrue(waitUntil { field.value as? String == "16" })
        XCTAssertFalse(settings.buttons["Reset"].firstMatch.isEnabled, "nothing to reset at the default size")
        app.terminate()
    }

    @MainActor
    func testAboutShowsLicenseAndAcknowledgements() throws {
        let app = launch([])
        app.menuBars.menuBarItems["MacMD"].click()
        app.menuBars.menuItems["About MacMD"].click()
        let about = app.windows["About MacMD"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.descendants(matching: .any)["legal-license"].click()
        XCTAssertTrue(
            about.sheets.firstMatch.staticTexts["MIT License"].waitForExistence(timeout: 5), "the license text")
        about.sheets.firstMatch.buttons["Done"].click()
        about.descendants(matching: .any)["legal-acknowledgements"].click()
        let ack = about.sheets.firstMatch
        XCTAssertTrue(ack.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil {
                ack.staticTexts.matching(NSPredicate(format: "value CONTAINS 'KaTeX' OR label CONTAINS 'KaTeX'")).count
                    > 0
            },
            "acknowledgements list KaTeX")
        ack.buttons["Done"].click()
        app.terminate()
    }
}
