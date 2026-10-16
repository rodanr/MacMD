import AppKit
import MacMDKit
import Synchronization
import UniformTypeIdentifiers

/// The AppKit document: file I/O, autosave, versions, undo and window management.
final class MarkdownDocument: NSDocument {
    let model = DocumentModel()

    override class var autosavesInPlace: Bool { true }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    override var fileURL: URL? {
        didSet {
            // May be called from the file presenter queue (rename, move); never block on main here.
            let url = fileURL
            Task { @MainActor in self.model.fileURL = url }
        }
    }

    /// The encoding the file was read with, so saving never silently converts it. NSDocument reads and
    /// writes on background threads too, hence the lock.
    private struct FileFormat {
        var encoding: String.Encoding = .utf8
        var hasByteOrderMark = false
    }
    private let format = Mutex(FileFormat())

    // MARK: Reading & writing

    override func read(from data: Data, ofType typeName: String) throws {
        guard let decoded = Self.decode(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        format.withLock { $0 = FileFormat(encoding: decoded.encoding, hasByteOrderMark: decoded.hasByteOrderMark) }
        onMain { self.model.replaceText(decoded.text) }
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = onMain { self.model.text }
        let current = format.withLock { $0 }
        if current.encoding == .utf8 {
            return (current.hasByteOrderMark ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(text.utf8)
        }
        guard let data = text.data(using: current.encoding) else {
            // The text gained characters the original encoding can't hold: fall back to UTF-8.
            format.withLock { $0 = FileFormat() }
            return Data(text.utf8)
        }
        return data
    }

    /// Decodes UTF-8 (with or without BOM), falling back to Foundation's encoding detection.
    nonisolated static func decode(_ data: Data) -> (text: String, encoding: String.Encoding, hasByteOrderMark: Bool)? {
        if let text = String(data: data, encoding: .utf8) {
            let bom = text.hasPrefix("\u{FEFF}")
            return (bom ? String(text.dropFirst()) : text, .utf8, bom)
        }
        var converted: NSString?
        let raw = NSString.stringEncoding(
            for: data, encodingOptions: [.allowLossyKey: false], convertedString: &converted, usedLossyConversion: nil)
        guard raw != 0, let text = converted as String? else { return nil }
        return (text, String.Encoding(rawValue: raw), false)
    }

    /// NSDocument calls I/O overrides on the main thread (concurrent reading and asynchronous
    /// writing are off), but they are not annotated as such; hop explicitly if that ever changes.
    private nonisolated func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }

    // MARK: External changes

    override func presentedItemDidChange() {
        super.presentedItemDidChange()
        Task { @MainActor in self.reloadIfChangedOnDisk() }
    }

    /// Silently reloads when another app changed the file and there are no unsaved edits here.
    private func reloadIfChangedOnDisk() {
        guard let fileURL, let fileType, !isDocumentEdited,
            let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            let known = fileModificationDate, modified > known
        else { return }
        do {
            try revert(toContentsOf: fileURL, ofType: fileType)
        } catch {
            presentError(error)
        }
    }

    /// An untitled document saves into the folder it was created in (its Files sidebar folder).
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if fileURL == nil, let folder = model.browsedFolder {
            savePanel.directoryURL = folder
        }
        return super.prepareSavePanel(savePanel)
    }

    // MARK: Printing

    override func printDocument(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        Exporter.print(markdown: model.text, baseURL: fileURL?.deletingLastPathComponent(), window: window)
    }
}
