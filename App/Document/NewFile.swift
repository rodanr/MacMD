import AppKit
import MacMDKit

/// Creates Markdown files in a folder: the File menu, the Open panel and the Files sidebar all use this.
@MainActor
enum NewFile {
    /// Asks for a name, creates the empty file in `folder` and opens it. The new document browses `browsing`
    /// when it's inside it (so the Files sidebar keeps its place), otherwise `folder`.
    static func create(in folder: URL, browsing: URL? = nil) {
        guard let url = askAndCreate(in: folder) else { return }
        LinkRouter.openFile(url, browsing: browsing ?? folder)
    }

    /// Asks for a name and creates the empty file. Nil when cancelled or refused (with the reason shown).
    static func askAndCreate(in folder: URL) -> URL? {
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let alert = NSAlert()
        alert.messageText = "New File"
        alert.informativeText = "Create a Markdown file in “\(folder.lastPathComponent)”."
        let field = NSTextField(string: NewFileName.unique("Untitled.md", existing: existing))
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.setAccessibilityIdentifier("new-file-name")
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.setAccessibilityIdentifier("new-file")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        guard let name = NewFileName.normalized(field.stringValue) else {
            showError(
                "“\(field.stringValue)” can’t be used as a file name.",
                "Names can’t be empty, start with a dot, or contain “/” or “:”.")
            return nil
        }
        let url = folder.appending(path: name)
        do {
            // Never replaces a file, even one created since the name was suggested.
            try Data().write(to: url, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            showError("“\(name)” already exists in “\(folder.lastPathComponent)”.", "Choose a different name.")
            return nil
        } catch {
            NSApp.presentError(error)
            return nil
        }
        return url
    }

    private static func showError(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
