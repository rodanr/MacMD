import AppKit
import MacMDKit

/// What the Files sidebar's rows can do: create, rename and trash files and folders. Moves and deletions are
/// coordinated, so an open document follows a rename and keeps its text when its file is trashed.
@MainActor
enum FileActions {
    static func newFile(in folder: URL, model: DocumentModel) {
        NewFile.create(in: folder, browsing: model.browsedFolder, expanding: model.expandedFolders)
    }

    /// Creates a folder and selects it, so the next New File goes into it.
    static func newFolder(in folder: URL, model: DocumentModel) {
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        guard
            let name = NamePrompt.ask(
                title: "New Folder", message: "Create a folder in “\(folder.lastPathComponent)”.",
                suggested: NewFileName.unique("New Folder", existing: existing), action: "Create",
                normalize: NewFileName.normalizedFolder)
        else { return }
        let url = folder.appending(path: name, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch CocoaError.fileWriteFileExists {
            NamePrompt.showExists(name, in: folder)
            return
        } catch {
            NSApp.presentError(error)
            return
        }
        model.expandedFolders.insert(FileNavigation.realPath(folder))
        model.expandedFolders.insert(FileNavigation.realPath(url))
        model.selectedFolder = url
    }

    static func rename(_ url: URL, isDirectory: Bool, model: DocumentModel) {
        let folder = url.deletingLastPathComponent()
        guard
            let name = NamePrompt.ask(
                title: "Rename", message: "Rename “\(url.lastPathComponent)”.", suggested: url.lastPathComponent,
                action: "Rename", normalize: isDirectory ? NewFileName.normalizedFolder : NewFileName.normalized)
        else { return }
        guard name != url.lastPathComponent else { return }
        let destination = folder.appending(path: name)
        // Only a change of case may land on an existing name (the same file on a case-insensitive disk).
        if FileManager.default.fileExists(atPath: destination.path),
            name.lowercased() != url.lastPathComponent.lowercased()
        {
            NamePrompt.showExists(name, in: folder)
            return
        }
        let oldPath = FileNavigation.realPath(url)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var moveError: Error?
        coordinator.coordinate(
            writingItemAt: url, options: .forMoving, writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { from, to in
            do {
                coordinator.item(at: from, willMoveTo: to)
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError {
            NSApp.presentError(error)
            return
        }
        if isDirectory { model.folderDidMove(from: oldPath, to: destination) }
    }

    /// Moves to the Trash after asking, so it can be put back from Finder.
    static func moveToTrash(_ url: URL, isDirectory: Bool) {
        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to the Trash?"
        alert.informativeText =
            isDirectory
            ? "The folder and everything in it can be put back from the Trash in Finder."
            : "You can put it back from the Trash in Finder."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var coordinationError: NSError?
        var trashError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { item in
            do {
                try FileManager.default.trashItem(at: item, resultingItemURL: nil)
            } catch {
                trashError = error
            }
        }
        if let error = coordinationError ?? trashError { NSApp.presentError(error) }
    }

    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
