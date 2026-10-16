import AppKit
import MacMDKit

/// Opens links clicked in documents and files picked in the app: Markdown files in MacMD, everything else in
/// its default app.
@MainActor
enum LinkRouter {
    static let webSchemes: Set<String> = ["http", "https", "mailto"]

    /// Web links open in the browser and local Markdown opens in MacMD. Other local files are only
    /// revealed in Finder, so a link in a document can never launch an app or a script.
    /// `source` is the document the link is in: the opened file keeps browsing its folder.
    static func open(_ url: URL, from source: DocumentModel? = nil) {
        let scheme = url.scheme?.lowercased() ?? ""
        let (link, anchor) = FileNavigation.splitFragment(url)
        let file: URL
        if scheme == ReaderPage.scheme, url.host() == "file" {
            file = URL(filePath: link.path(percentEncoded: false))
        } else if scheme == "file" {
            file = link
        } else {
            if webSchemes.contains(scheme) { NSWorkspace.shared.open(url) }
            return
        }
        // A section of the document the link is in: stay here.
        if let source, let anchor, let current = source.fileURL,
            current.standardizedFileURL.resolvingSymlinksInPath() == file.standardizedFileURL.resolvingSymlinksInPath()
        {
            source.reveal(anchor: anchor)
            return
        }
        openFile(
            file, browsing: source?.browsedFolder ?? source?.fileURL?.deletingLastPathComponent(),
            expanding: source?.expandedFolders ?? [], anchor: anchor)
    }

    /// `browsing` is the folder the file was opened from (the Files sidebar's, or the linking document's).
    /// A newly opened document keeps browsing it when the file is inside it, so moving between files doesn't
    /// lose your place, with the folders in `expanding` still open. `anchor` is a section to show.
    static func openFile(
        _ fileURL: URL, browsing folder: URL? = nil, expanding: Set<String> = [], anchor: String? = nil
    ) {
        guard MarkdownFile.isMarkdown(fileURL) else {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return
        }
        // Not displayed yet: the window should appear with the right folder, not switch to it.
        NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: false) {
            document, wasAlreadyOpen, error in
            if let error {
                // A missing or unreadable file: say so instead of doing nothing.
                NSDocumentController.shared.presentError(error)
                return
            }
            guard let document else { return }
            if let document = document as? MarkdownDocument {
                if !wasAlreadyOpen {
                    let browsed = FileNavigation.folderToBrowse(opening: fileURL, from: folder)
                    document.model.browsedFolder = browsed
                    if browsed == folder { document.model.expandedFolders.formUnion(expanding) }
                }
                if let anchor { document.model.reveal(anchor: anchor) }
            }
            if document.windowControllers.isEmpty { document.makeWindowControllers() }
            document.showWindows()
        }
    }
}
