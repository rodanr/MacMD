import XCTest

/// Smoke tests: the app launches, opens a document, styles it and switches to Read mode.
/// Screenshots are attached to the result bundle for visual review.
final class MacMDUITests: XCTestCase {
    private var fixture: String {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Packages/MacMDKit/Tests/MacMDKitTests/Fixtures/kitchen-sink.md").path
    }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testOpenEditAndRead() throws {
        for appearance in ["light", "dark"] {
            let app = launch([
                fixture, "-appearance", appearance,
                // A fixed window size, so README screenshots don't depend on how the user last sized the window.
                "-NSWindow Frame MarkdownDocumentWindow", "120 120 1200 780 0 0 2560 1410",
            ])

            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 10))
            let editor = window.textViews["editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertTrue((editor.value as? String)?.hasPrefix("# Welcome to MacMD") == true)
            attach(window, "edit-\(appearance)")
            editor.scroll(byDeltaX: 0, deltaY: -900)
            attach(window, "edit-\(appearance)-2")

            app.typeKey("e", modifierFlags: .command)
            let reader = window.webViews.firstMatch
            XCTAssertTrue(reader.waitForExistence(timeout: 5))
            XCTAssertTrue(reader.staticTexts["Welcome to MacMD"].waitForExistence(timeout: 10))
            attach(window, "read-\(appearance)")
            reader.scroll(byDeltaX: 0, deltaY: -1000)
            attach(window, "read-\(appearance)-2")

            app.typeKey("e", modifierFlags: .command)
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testWritingModesAndZoom() throws {
        let app = launch([
            fixture, "-appearance", "dark",
        ])
        let window = app.windows.firstMatch
        let editor = window.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()

        app.typeKey(.F8, modifierFlags: [])
        XCTAssertTrue(window.buttons["Focus"].waitForExistence(timeout: 3), "focus mode shows a status chip")
        app.typeKey(.F9, modifierFlags: [])
        XCTAssertTrue(window.buttons["Typewriter"].waitForExistence(timeout: 3), "typewriter mode shows a chip")
        editor.typeKey(.downArrow, modifierFlags: [])
        editor.typeKey(.downArrow, modifierFlags: [])
        attach(window, "focus-typewriter")
        window.buttons["Focus"].click()
        XCTAssertFalse(window.buttons["Focus"].exists, "clicking the chip turns the mode off")
        app.typeKey(.F9, modifierFlags: [])

        let zoom = window.descendants(matching: .any)["zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 3))
        app.typeKey("=", modifierFlags: .command)
        app.typeKey("=", modifierFlags: .command)
        XCTAssertTrue(waitForText("125%", of: zoom), "status bar shows the new zoom")
        window.descendants(matching: .any)["sidebarToggle"].firstMatch.click()  // the outline zooms too
        XCTAssertTrue(window.buttons["Lists"].waitForExistence(timeout: 3), "the toolbar button shows the outline")
        attach(window, "zoom-125")
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(waitForText("100%", of: zoom), "⌘0 returns to actual size")
        app.terminate()
    }

    @MainActor
    func testLineWidthAppliesToBothModes() throws {
        let app = launch([
            fixture, "-lineWidth", "narrow", "-appearance", "light",
            "-NSWindow Frame MarkdownDocumentWindow",
            "120 120 1200 780 0 0 2560 1410",
        ])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
        attach(window, "width-narrow-edit")

        // Change it at runtime, the way a user does: View Options → Line Width → Full.
        window.toolbars.descendants(matching: .any)["viewOptions"].firstMatch.click()
        app.menuItems["Line Width"].hover()
        app.menuItems["Full"].click()
        attach(window, "width-full-edit")

        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(window.webViews.firstMatch.staticTexts["Welcome to MacMD"].waitForExistence(timeout: 10))
        attach(window, "width-full-read")
        app.terminate()
    }

    @MainActor
    func testOpeningAFileFromTheFilesSidebarKeepsTheSidebar() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["alpha.md", "beta.md"] {
            try "# \(name)\n".write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
        }

        let app = launch([folder.appending(path: "alpha.md").path])
        let first = app.windows["alpha.md"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        app.typeKey("2", modifierFlags: [.command, .control])
        XCTAssertTrue(first.buttons["beta.md"].waitForExistence(timeout: 5), "the Files sidebar lists the folder")

        first.buttons["beta.md"].click()
        let second = app.windows["beta.md"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertTrue(
            second.buttons["alpha.md"].waitForExistence(timeout: 5),
            "the opened file keeps the Files sidebar open on the same folder")
        attach(second, "files-sidebar-after-open")

        // Hiding and showing the sidebar again still shows the files.
        app.typeKey("s", modifierFlags: [.command, .control])
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(second.buttons["alpha.md"].waitForExistence(timeout: 5), "files come back after reopening")
        app.terminate()
    }

    @MainActor
    func testVimMode() throws {
        // A scratch copy: the app autosaves in place, and the fixture must stay untouched.
        let file = FileManager.default.temporaryDirectory.appending(path: "vim-\(UUID().uuidString).md")
        try "# Title\n\nsecond line\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let app = launch([file.path, "-vimMode", "YES"])
        let window = app.windows.firstMatch
        let editor = window.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let status = window.staticTexts["vimStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.value as? String, "NORMAL")

        editor.typeText("x")
        XCTAssertEqual(editor.value as? String, " Title\n\nsecond line\n", "x deletes in normal mode")
        editor.typeText("u")
        XCTAssertEqual(editor.value as? String, "# Title\n\nsecond line\n", "u undoes")

        editor.typeText("jjcwfirst")
        XCTAssertEqual(status.value as? String, "INSERT")
        editor.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(status.value as? String, "NORMAL")
        XCTAssertEqual(editor.value as? String, "# Title\n\nfirst line\n", "cw changes a word")
        attach(window, "vim-normal")

        editor.typeText("Vd")
        XCTAssertEqual(editor.value as? String, "# Title\n\n", "visual line delete")
        app.terminate()
    }

    @MainActor
    func testSettingsChooseHowDocumentsOpen() throws {
        for appearance in ["light", "dark"] {
            let app = launch([
                fixture, "-appearance", appearance, "-openInReadMode", "YES",
            ])
            let window = app.windows["kitchen-sink.md"]
            XCTAssertTrue(window.waitForExistence(timeout: 10))
            XCTAssertTrue(
                window.webViews.firstMatch.staticTexts["Welcome to MacMD"].waitForExistence(timeout: 10),
                "the document opens in Read mode")

            app.typeKey(",", modifierFlags: .command)
            let settings = app.windows["Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertTrue(settings.descendants(matching: .any)["openModePicker"].exists)
            attach(settings, "settings-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testAboutWindowShowsTerms() throws {
        for appearance in ["light", "dark"] {
            let app = launch(["-appearance", appearance])
            app.menuBars.menuBarItems["MacMD"].click()
            app.menuBars.menuItems["About MacMD"].click()

            let about = app.windows["About MacMD"]
            XCTAssertTrue(about.waitForExistence(timeout: 5))
            XCTAssertTrue(about.staticTexts["Made by Rodan Ramdam"].exists)
            attach(about, "about-\(appearance)")

            about.descendants(matching: .any)["legal-terms"].click()
            let sheet = about.sheets.firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            XCTAssertTrue(sheet.staticTexts["No warranty"].waitForExistence(timeout: 5))
            attach(about, "terms-\(appearance)")
            sheet.buttons["Done"].click()
            app.terminate()
        }
    }

    @MainActor
    func testListContinuationAndUndo() throws {
        let app = launch([])
        let editor = app.windows.firstMatch.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()

        editor.typeText("- one\n")
        XCTAssertEqual(editor.value as? String, "- one\n- ")
        editor.typeText("two\n\n")
        // Return on an empty item ends the list.
        XCTAssertEqual(editor.value as? String, "- one\n- two\n")

        app.typeKey("z", modifierFlags: .command)
        XCTAssertNotEqual(editor.value as? String, "- one\n- two\n")

        // Close without saving the untitled document.
        app.typeKey("w", modifierFlags: .command)
        let dontSave = app.sheets.buttons["Delete"].exists ? app.sheets.buttons["Delete"] : app.buttons["Don’t Save"]
        if dontSave.waitForExistence(timeout: 2) { dontSave.click() }
        app.terminate()
    }

    @MainActor
    func testExportPDFAndHTML() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "macmd-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = launch([fixture])
        XCTAssertTrue(app.windows.firstMatch.textViews["editor"].waitForExistence(timeout: 10))

        export(app, "Export as PDF…", to: directory.appending(path: "out.pdf"))
        export(app, "Export as HTML…", to: directory.appending(path: "out.html"))

        let pdf = try Data(contentsOf: directory.appending(path: "out.pdf"))
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        XCTAssertGreaterThan(pdf.count, 10_000)
        let html = try String(contentsOf: directory.appending(path: "out.html"), encoding: .utf8)
        XCTAssertTrue(html.contains("Welcome to MacMD"))
        XCTAssertTrue(html.contains("<svg"), "Mermaid diagram should be pre-rendered")
        XCTAssertTrue(html.contains("class=\"katex"), "Math should be pre-rendered")
        XCTAssertFalse(html.contains("<script"))
        app.terminate()
    }

    /// Exported HTML opens in browsers, outside MacMD: a hostile document must not export working script.
    @MainActor
    func testExportedHTMLCannotRunScripts() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "macmd-hostile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "hostile.md")
        try """
        # Hostile

        <img src="x" onerror="alert('img')">
        <a href="javascript:alert('link')">click</a>
        <div onclick="alert('div')">text</div>
        <script>alert('script')</script>
        """.write(to: file, atomically: true, encoding: .utf8)

        let app = launch([file.path])
        XCTAssertTrue(app.windows.firstMatch.textViews["editor"].waitForExistence(timeout: 10))
        export(app, "Export as HTML…", to: directory.appending(path: "out.html"))

        let html = try String(contentsOf: directory.appending(path: "out.html"), encoding: .utf8).lowercased()
        XCTAssertTrue(html.contains("hostile"))
        XCTAssertTrue(html.contains("content-security-policy"), "exports carry a no-script policy")
        for forbidden in ["<script", "onerror", "onclick", "javascript:"] {
            XCTAssertFalse(html.contains(forbidden), "exported HTML still contains \(forbidden)")
        }
        app.terminate()
    }

    /// Read mode must not run scripts from documents or let them navigate away.
    @MainActor
    func testReaderIgnoresHostileHTML() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "hostile-\(UUID().uuidString).md")
        try """
        # Safe heading

        <script>document.body.innerHTML = '<h1>HACKED</h1>'</script>
        <img src="x.png" onerror="document.body.innerHTML = '<h1>HACKED</h1>'">
        <meta http-equiv="refresh" content="0;url=https://example.com">
        """.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let app = launch([file.path])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
        app.typeKey("e", modifierFlags: .command)
        let reader = window.webViews.firstMatch
        XCTAssertTrue(reader.staticTexts["Safe heading"].waitForExistence(timeout: 10))
        // Give a refresh or script time to act, then make sure the document is still shown.
        XCTAssertFalse(reader.staticTexts["HACKED"].waitForExistence(timeout: 3))
        XCTAssertTrue(reader.staticTexts["Safe heading"].exists)
        app.terminate()
    }

    /// Runs an export command and saves to `url` through the save panel.
    private func export(_ app: XCUIApplication, _ item: String, to url: URL) {
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems[item].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        // Go to the target folder, then name the file.
        sheet.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(url.deletingLastPathComponent().path + "\n")
        let nameField = sheet.textFields.firstMatch
        nameField.doubleClick()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText(url.lastPathComponent + "\n")
        let exists = expectation(
            for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }, evaluatedWith: nil)
        wait(for: [exists], timeout: 30)
    }

    /// Launches the app with known settings, so a test never depends on the preferences of the Mac it runs on.
    /// `arguments` are files to open plus `-key value` overrides.
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let pinned = [
            "-ApplePersistenceIgnoreState": "YES", "-vimMode": "NO", "-openInReadMode": "NO", "-zoom": "1",
            "-focusMode": "NO", "-typewriterMode": "NO", "-lineWidth": "medium", "-theme": "paper",
            "-sidebarVisible": "NO", "-sidebarTab": "outline",
        ]
        var all = arguments
        for (key, value) in pinned.sorted(by: { $0.key < $1.key }) where !arguments.contains(key) {
            all += [key, value]
        }
        let app = XCUIApplication()
        app.launchArguments = all
        app.launch()
        return app
    }

    private func waitForText(_ title: String, of element: XCUIElement) -> Bool {
        // Xcode versions differ in whether a SwiftUI menu's text is exposed as its title or its label.
        let predicate = NSPredicate(format: "title == %@ OR label == %@", title, title)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    /// Attaches a screenshot of `element` for visual review. Set `MACMD_SKIP_SCREENSHOTS=1` (pass it to
    /// xcodebuild as `TEST_RUNNER_MACMD_SKIP_SCREENSHOTS=1`) when no display can be captured.
    private func attach(_ element: XCUIElement, _ name: String) {
        guard ProcessInfo.processInfo.environment["MACMD_SKIP_SCREENSHOTS"] != "1" else { return }
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
