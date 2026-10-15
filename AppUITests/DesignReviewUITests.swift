import XCTest

/// Captures every theme in light and dark, in both modes, for visual review. Assertions are light;
/// the screenshots are the product.
final class DesignReviewUITests: XCTestCase {
    @MainActor
    func testCaptureThemes() throws {
        for theme in ["paper", "clean", "mono"] {
            for appearance in ["light", "dark"] {
                let app = launch([
                    fixture, "-theme", theme, "-appearance", appearance, "-sidebarVisible", "YES",
                    "-sidebarTab", "outline",
                    // Fits the 1024×768 screens of CI runners.
                    "-NSWindow Frame MarkdownDocumentWindow", "40 60 980 680 0 0 1024 768",
                ])
                let window = app.windows.firstMatch
                XCTAssertTrue(window.waitForExistence(timeout: 10))
                XCTAssertTrue(window.textViews["editor"].waitForExistence(timeout: 10))
                attach(window, "review-\(theme)-\(appearance)-edit")

                app.typeKey("e", modifierFlags: .command)
                let reader = window.webViews.firstMatch
                XCTAssertTrue(reader.waitForExistence(timeout: 5))
                XCTAssertTrue(reader.staticTexts["Welcome to MacMD"].waitForExistence(timeout: 10))
                reader.scroll(byDeltaX: 0, deltaY: -900)
                attach(window, "review-\(theme)-\(appearance)-read")
                reader.scroll(byDeltaX: 0, deltaY: -1200)
                attach(window, "review-\(theme)-\(appearance)-read-2")

                if theme == "paper" {
                    app.typeKey(",", modifierFlags: .command)
                    let settings = app.windows["Settings"]
                    XCTAssertTrue(settings.waitForExistence(timeout: 5))
                    attach(settings, "review-settings-\(appearance)")
                }
                app.terminate()
            }
        }
    }
}
