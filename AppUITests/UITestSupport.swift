import XCTest

/// Shared helpers for the UI tests.
extension XCTestCase {
    /// The kitchen-sink document from the MacMDKit fixtures.
    var fixture: String {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Packages/MacMDKit/Tests/MacMDKitTests/Fixtures/kitchen-sink.md").path
    }

    /// A fresh folder for one test's files, removed when the test ends.
    func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "macmd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// Waits until `condition` is true, polling. Returns false on timeout.
    func waitUntil(timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The print panel looks for network printers, so macOS may ask whether MacMD can "find devices on local
    /// networks". The prompt stays up and covers menus in later tests; answer it with Don't Allow.
    func dismissLocalNetworkPrompt(wait timeout: TimeInterval) {
        let prompts = XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter")
        // The prompt's buttons carry their text as a title, not a label.
        let dontAllow = prompts.buttons.matching(NSPredicate(format: "title BEGINSWITH 'Don'")).firstMatch
        if dontAllow.waitForExistence(timeout: timeout) { dontAllow.click() }
    }

    /// Scrolls `window`'s scroll view down until `element` can be clicked (small screens shorten Settings).
    func reveal(_ element: XCUIElement, in window: XCUIElement) {
        for _ in 0..<5 where !element.isHittable {
            window.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -400)
        }
    }

    /// Picks `item` from `submenu` of the `menu` menu bar item, waiting for the submenu to open
    /// (hovering opens it after a delay that varies between machines).
    func choose(_ item: String, in submenu: String, of menu: String, _ app: XCUIApplication) {
        app.menuBars.menuBarItems[menu].click()
        let parent = app.menuBars.menuItems[submenu]
        let target = app.menuBars.menuItems[item]
        parent.hover()
        if !waitUntil(timeout: 3, { target.isHittable }) {
            parent.click()
            XCTAssertTrue(waitUntil { target.isHittable }, "\(menu) → \(submenu) → \(item) opens")
        }
        target.click()
    }

    func export(_ app: XCUIApplication, _ item: String, to url: URL) {
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
    func launch(_ arguments: [String]) -> XCUIApplication {
        let pinned = [
            "-ApplePersistenceIgnoreState": "YES", "-vimMode": "NO", "-openInReadMode": "NO", "-zoom": "1",
            "-fontSize": "16",
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
        dismissLocalNetworkPrompt(wait: 0)
        return app
    }

    func waitForText(_ title: String, of element: XCUIElement) -> Bool {
        // Xcode versions differ in whether a SwiftUI menu's text is exposed as its title or its label.
        let predicate = NSPredicate(format: "title == %@ OR label == %@", title, title)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    /// Attaches a screenshot of `element` for visual review. Set `MACMD_SKIP_SCREENSHOTS=1` (pass it to
    /// xcodebuild as `TEST_RUNNER_MACMD_SKIP_SCREENSHOTS=1`) when no display can be captured.
    func attach(_ element: XCUIElement, _ name: String) {
        guard ProcessInfo.processInfo.environment["MACMD_SKIP_SCREENSHOTS"] != "1" else { return }
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
