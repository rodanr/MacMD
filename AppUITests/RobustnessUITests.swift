import AppKit
import XCTest

/// What happens when things go wrong or get pushed: odd files, files changing underneath an open
/// document, fast typing, pasted images, and Vim mode in the real editor.
final class RobustnessUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

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

    /// The title bar says "Edited" once a document has unsaved changes.
    private func isEdited(_ window: XCUIElement) -> Bool {
        window.staticTexts["Edited"].exists
    }

    // MARK: Dirty state

    @MainActor
    func testStylingZoomThemesAndModesNeverMarkTheDocumentEdited() throws {
        let app = launch([fixture])
        let window = app.windows.firstMatch
        XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
        app.typeKey("=", modifierFlags: .command)
        app.typeKey("0", modifierFlags: .command)
        app.typeKey("e", modifierFlags: .command)
        app.typeKey("e", modifierFlags: .command)
        app.typeKey(.F8, modifierFlags: [])
        app.typeKey(.F8, modifierFlags: [])
        choose("Mono", in: "Theme", of: "View", app)
        sleep(2)
        XCTAssertFalse(isEdited(window), "nothing here changes the text, so the document stays unedited")
        choose("Paper", in: "Theme", of: "View", app)
        app.terminate()
    }

    // MARK: Appearance

    /// Diagrams bake their colors in, so Read mode redraws them when the appearance flips. The check samples the
    /// screen (reader.js also tags each diagram with `data-scheme`, but web content attributes don't reach XCUITest).
    @MainActor
    func testDiagramRedrawsOnAppearanceChange() throws {
        // `-appearance` comes from the command line, so flipping it in Settings is never saved.
        let app = launch([fixture, "-openInReadMode", "YES", "-appearance", "light"])
        let window = app.windows["kitchen-sink.md"]
        let reader = window.webViews.firstMatch
        let diagramLabel = reader.staticTexts["Write"].firstMatch
        XCTAssertTrue(diagramLabel.waitForExistence(timeout: 15), "the diagram is drawn")
        reader.scroll(byDeltaX: 0, deltaY: -5000)  // the diagram is near the end of the page
        // Inside the "Write" node, just left of its label: the node's fill, which Mermaid bakes in when drawing.
        func nodeFill() -> Double? {
            guard diagramLabel.exists else { return nil }
            let label = diagramLabel.frame
            return brightness(at: CGPoint(x: label.minX - 4, y: label.midY), in: window)
        }
        // Without a display to capture (MACMD_SKIP_SCREENSHOTS), only check that the diagram is drawn again.
        let canSample = ProcessInfo.processInfo.environment["MACMD_SKIP_SCREENSHOTS"] != "1"
        if canSample {
            XCTAssertTrue(waitUntil(timeout: 5) { (nodeFill() ?? 0) > 0.5 }, "the diagram is drawn for light mode")
        }
        attach(window, "diagram-light")

        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.radioButtons["Dark"].firstMatch.click()
        settings.typeKey("w", modifierFlags: .command)  // keep Settings out of the screenshot
        XCTAssertTrue(
            waitUntil(timeout: 10) { canSample ? (nodeFill() ?? 1) < 0.5 : diagramLabel.exists },
            "the diagram is drawn again in dark colors, not left as source, an error or light colors")
        attach(window, "diagram-dark")
        app.terminate()
    }

    /// Brightness (0–1) of the pixel at `point` (screen coordinates) in a screenshot of `window`.
    private func brightness(at point: CGPoint, in window: XCUIElement) -> Double? {
        let frame = window.frame
        guard frame.width > 0,
            let image = window.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let scale = CGFloat(image.width) / frame.width
        let x = Int((point.x - frame.minX) * scale)
        let y = Int((point.y - frame.minY) * scale)
        guard (0..<image.width).contains(x), (0..<image.height).contains(y) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // Core Graphics counts rows from the bottom: shift the image so the wanted pixel lands on (0, 0).
            context.draw(
                image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        return Double(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 765
    }

    // MARK: Odd files

    @MainActor
    func testBinaryFileShowsAnErrorInsteadOfCrashing() throws {
        let file = try temporaryFolder().appending(path: "image.md")
        var bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0xFF, 0xFE, 0x00, 0xD8])
        bytes.append(contentsOf: (0..<4096).map { _ in UInt8.random(in: 0...255) })
        try bytes.write(to: file)
        let app = launch([file.path])
        // Either a readable fallback or an error alert is fine; the app must keep running.
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                app.windows.firstMatch.textViews["editor"].exists || app.dialogs.count > 0 || app.alerts.count > 0
            })
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    @MainActor
    func testEmptyAndWhitespaceFilesOpen() throws {
        for content in ["", "\n\n\n", "   ", "\u{FEFF}"] {
            let (app, editor, _) = try open(content)
            app.typeKey("e", modifierFlags: .command)
            XCTAssertTrue(app.windows.firstMatch.webViews.firstMatch.waitForExistence(timeout: 10))
            app.typeKey("e", modifierFlags: .command)
            XCTAssertTrue(editor.exists)
            app.terminate()
        }
    }

    @MainActor
    func testDeletingTheOpenFileKeepsTheTextAndOffersToSaveIt() throws {
        let (app, editor, file) = try open("keep me")
        try FileManager.default.removeItem(at: file)
        sleep(2)
        XCTAssertEqual(value(editor), "keep me", "the text stays on screen")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("!")
        editor.typeKey("s", modifierFlags: .command)
        // macOS asks where to save a document whose file is gone; nothing is lost meanwhile.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.staticTexts["You can specify where to save it."].exists)
        XCTAssertEqual(value(editor), "keep me!")
        app.terminate()
    }

    @MainActor
    func testUnsavedEditsSurviveAChangeFromAnotherApp() throws {
        let (app, editor, file) = try open("original")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText(" plus my edit")
        let autosaved = (try? String(contentsOf: file, encoding: .utf8)) == "original plus my edit"
        try "changed by another app".write(to: file, atomically: true, encoding: .utf8)
        sleep(3)
        if autosaved {
            // The edit was already saved, so the other app's newer version wins, as in TextEdit.
            XCTAssertEqual(value(editor), "changed by another app")
        } else {
            XCTAssertEqual(value(editor), "original plus my edit", "unsaved edits are never replaced by a reload")
        }
        app.terminate()
    }

    @MainActor
    func testRenamingTheOpenFileFollowsIt() throws {
        let (app, editor, file) = try open("# Renamed", name: "before.md")
        let renamed = file.deletingLastPathComponent().appending(path: "after.md")
        try FileManager.default.moveItem(at: file, to: renamed)
        XCTAssertTrue(app.windows["after.md"].waitForExistence(timeout: 10), "the window title follows the rename")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("!")
        editor.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 10) { (try? String(contentsOf: renamed, encoding: .utf8)) == "# Renamed!" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "no copy is left at the old name")
        app.terminate()
    }

    // MARK: Pasting

    @MainActor
    func testPastingAnImageSavesItNextToTheDocument() throws {
        let (app, editor, file) = try open("# Notes\n\n")
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.systemPink.setFill()
            rect.fill()
            return true
        }
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.writeObjects([image]))
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(waitUntil { self.value(editor).contains("![pasted-") }, "a link is inserted: \(value(editor))")
        let link = try XCTUnwrap(value(editor).firstMatch(of: /\]\((assets\/pasted-[^)]+\.png)\)/)?.output.1)
        let saved = file.deletingLastPathComponent().appending(path: String(link))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path), "the image is saved at \(link)")
        app.typeKey("e", modifierFlags: .command)
        let reader = app.windows.firstMatch.webViews.firstMatch
        XCTAssertTrue(reader.images.firstMatch.waitForExistence(timeout: 10), "Read mode shows the pasted image")
        app.terminate()
    }

    // MARK: Typing

    @MainActor
    func testFastTypingKeepsEveryCharacter() throws {
        let (app, editor, _) = try open(
            String(repeating: "Some **bold** text and a [link](https://example.com).\n\n", count: 300))
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        let typed = "# Heading\nA paragraph with **bold**, *italic*, `code` and $x^2$.\n- one\ntwo\n"
        let start = Date()
        editor.typeText(typed)
        XCTAssertLessThan(Date().timeIntervalSince(start), 30, "typing keeps up")
        // List continuation turns the "two" line into "- two".
        XCTAssertTrue(
            waitUntil {
                self.value(editor).hasSuffix(
                    "# Heading\nA paragraph with **bold**, *italic*, `code` and $x^2$.\n- one\n- two\n- ")
            })
        app.terminate()
    }

    // MARK: Vim

    @MainActor
    func testVimEditingInTheApp() throws {
        let (app, editor, file) = try open("one\ntwo\nthree\n", arguments: ["-vimMode", "YES"])
        let status = app.windows.firstMatch.staticTexts["vimStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))

        editor.typeText("ddp")
        XCTAssertEqual(value(editor), "two\none\nthree\n", "dd then p swaps lines")
        editor.typeText("u")
        XCTAssertEqual(value(editor), "two\nthree\n", "u undoes the paste")
        editor.typeText("u")
        XCTAssertEqual(value(editor), "one\ntwo\nthree\n", "u undoes the delete")

        editor.typeText("ggAx")
        editor.typeKey(.escape, modifierFlags: [])
        editor.typeText("j.")
        XCTAssertEqual(value(editor), "onex\ntwox\nthree\n", ". repeats the append")

        editor.typeText("/thr")
        editor.typeKey(.enter, modifierFlags: [])
        editor.typeText("x")
        XCTAssertEqual(value(editor), "onex\ntwox\nhree\n", "search moves to the match")

        editor.typeText(":w")
        editor.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 10) { (try? String(contentsOf: file, encoding: .utf8)) == "onex\ntwox\nhree\n" },
            ":w saves")
        XCTAssertEqual(status.value as? String, "NORMAL")
        app.terminate()
    }

    @MainActor
    func testVimKeysDoNothingInReadMode() throws {
        let (app, editor, _) = try open("keep\n", arguments: ["-vimMode", "YES"])
        app.typeKey("e", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.webViews.firstMatch.waitForExistence(timeout: 10))
        app.typeText("ddx")
        app.typeKey("e", modifierFlags: .command)
        XCTAssertEqual(value(editor), "keep\n", "Read mode keys never edit the hidden editor")
        app.terminate()
    }

    // MARK: Windows

    @MainActor
    func testClosingAnUnsavedNewDocumentAsks() throws {
        let app = launch([])
        let editor = app.windows.firstMatch.textViews["editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.click()
        editor.typeText("draft")
        app.typeKey("w", modifierFlags: .command)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "closing unsaved work asks first")
        let delete = sheet.buttons["Delete"].exists ? sheet.buttons["Delete"] : sheet.buttons["Don’t Save"]
        delete.click()
        app.terminate()
    }
}
