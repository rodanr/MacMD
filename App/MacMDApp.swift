import AppKit
import MacMDKit
import SwiftUI

@main
enum MacMDMain {
    static func main() {
        let app = NSApplication.shared
        // The first document controller created becomes the shared one.
        _ = MarkdownDocumentController()
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
        Self.filesFromCommandLine.isEmpty
    }

    /// `MacMD notes.md` opens the file, which makes the binary usable from a terminal.
    private func openFilesFromCommandLine() {
        for url in Self.filesFromCommandLine {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    /// Existing files named on the command line; `-key value` settings and folders are not documents.
    private static var filesFromCommandLine: [URL] {
        LaunchArguments.filePaths(in: CommandLine.arguments.dropFirst()).compactMap { path in
            let url = URL(filePath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { return nil }
            return url
        }
    }

    // MARK: Actions

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            // The form scrolls, so the window may be shorter than its content: it must fit small screens.
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .resizable]
            // The form's full height, measured unconstrained.
            let ideal = NSHostingView(rootView: SettingsView().fixedSize(horizontal: false, vertical: true)).fittingSize
            let available = (NSScreen.main?.visibleFrame.height ?? ideal.height) - 60
            window.setContentSize(NSSize(width: ideal.width, height: min(ideal.height, available)))
            window.contentMaxSize = NSSize(width: ideal.width, height: ideal.height)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(sender)
    }

    @objc func showAbout(_ sender: Any?) {
        AboutWindowController.shared.showWindow(sender)
    }

    /// File → New File in Folder…: next to the current document, or in a folder you pick.
    @objc func newFileInFolder(_ sender: Any?) {
        let model = (NSDocumentController.shared.currentDocument as? MarkdownDocument)?.model
        if let model, let folder = model.currentFolder {
            FileActions.newFile(in: folder, model: model)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder for the new Markdown file."
        if panel.runModal() == .OK, let folder = panel.url { NewFile.create(in: folder) }
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
