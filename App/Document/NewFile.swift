import AppKit
import MacMDKit

/// Creates Markdown files in a folder: the File menu, the Open panel and the Files sidebar all use this.
@MainActor
enum NewFile {
    /// Asks for a name, creates the empty file in `folder` and opens it. The new document browses `browsing`
    /// when it's inside it (so the Files sidebar keeps its place), otherwise `folder`, with `expanding` open.
    static func create(in folder: URL, browsing: URL? = nil, expanding: Set<String> = []) {
        guard let url = askAndCreate(in: folder) else { return }
        LinkRouter.openFile(url, browsing: browsing ?? folder, expanding: expanding)
    }

    /// Asks for a name and creates the empty file. Nil when cancelled or refused (with the reason shown).
    static func askAndCreate(in folder: URL) -> URL? {
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        guard
            let name = NamePrompt.ask(
                title: "New File", message: "Create a Markdown file in “\(folder.lastPathComponent)”.",
                suggested: NewFileName.unique("Untitled.md", existing: existing), action: "Create",
                normalize: NewFileName.normalized)
        else { return nil }
        let url = folder.appending(path: name)
        do {
            // Never replaces a file, even one created since the name was suggested.
            try Data().write(to: url, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            NamePrompt.showExists(name, in: folder)
            return nil
        } catch {
            NSApp.presentError(error)
            return nil
        }
        return url
    }
}

/// Asks for a file or folder name.
@MainActor
enum NamePrompt {
    /// The checked name, or nil when cancelled or invalid (the reason is shown).
    static func ask(
        title: String, message: String, suggested: String, action: String, normalize: (String) -> String?
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: suggested)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.setAccessibilityIdentifier("name-field")
        alert.accessoryView = field
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        alert.window.setAccessibilityIdentifier("name-prompt")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard let name = normalize(field.stringValue) else {
            showError(
                "“\(field.stringValue)” can’t be used as a name.",
                "Names can’t be empty, start with a dot, or contain “/” or “:”.")
            return nil
        }
        return name
    }

    static func showExists(_ name: String, in folder: URL) {
        showError("“\(name)” already exists in “\(folder.lastPathComponent)”.", "Choose a different name.")
    }

    static func showError(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
