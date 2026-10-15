import AppKit
import MacMDKit
import SwiftUI

@main
enum MacMDMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let settings = AppSettings.shared
    private var settingsWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        NSWindow.allowsAutomaticWindowTabbing = true
        settings.applyAppearance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        openFilesFromCommandLine()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !CommandLine.arguments.dropFirst().contains { Self.markdownFile(at: $0) != nil }
    }

    /// `MacMD notes.md` opens the file, which makes the binary usable from a terminal.
    private func openFilesFromCommandLine() {
        for url in CommandLine.arguments.dropFirst().compactMap(Self.markdownFile(at:)) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    private static func markdownFile(at argument: String) -> URL? {
        guard !argument.hasPrefix("-") else { return nil }
        let url = URL(filePath: argument).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Actions

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(sender)
    }

    @objc func showAbout(_ sender: Any?) {
        AboutWindowController.shared.showWindow(sender)
    }

    @objc func checkForUpdates(_ sender: Any?) { UpdateChecker.checkForUpdates() }

    @objc func setTheme(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let theme = Theme.ID(rawValue: id) {
            settings.themeID = theme
        }
    }

    @objc func zoomIn(_ sender: Any?) { changeZoom { $0.zoomIn() } }
    @objc func zoomOut(_ sender: Any?) { changeZoom { $0.zoomOut() } }
    @objc func resetZoom(_ sender: Any?) { changeZoom { $0.resetZoom() } }

    @objc func increaseFontSize(_ sender: Any?) { changeFontSize { $0.increaseFontSize() } }
    @objc func decreaseFontSize(_ sender: Any?) { changeFontSize { $0.decreaseFontSize() } }

    private func changeFontSize(_ change: (AppSettings) -> Void) {
        change(settings)
        HUD.shared.show("Font Size \(FontSize.describe(settings.fontSize))")
    }

    private func changeZoom(_ change: (AppSettings) -> Void) {
        change(settings)
        HUD.shared.show("Zoom \(Zoom.describe(settings.zoom))")
    }

    @objc func openHelp(_ sender: Any?) { NSWorkspace.shared.open(AppInfo.help) }
    @objc func openMarkdownGuide(_ sender: Any?) { NSWorkspace.shared.open(AppInfo.markdownGuide) }
    @objc func reportIssue(_ sender: Any?) { NSWorkspace.shared.open(AppInfo.issues) }
    @objc func openReleaseNotes(_ sender: Any?) { NSWorkspace.shared.open(AppInfo.releases) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setTheme(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == settings.themeID.rawValue ? .on : .off
        }
        return true
    }
}
