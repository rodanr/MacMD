import AppKit
import MacMDKit
import Observation
import SwiftUI

/// Per-document UI state shared by the editor, the reader, the sidebar and the status bar.
///
/// The `NSTextStorage` is the single source of truth for the text; everything else
/// (outline, statistics) is derived from it with a short debounce.
@MainActor @Observable
final class DocumentModel {
    enum Mode: String { case edit, read }

    enum SidebarTab: String, CaseIterable, Identifiable {
        case outline, files
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    /// Above this size live styling is turned off to keep typing instant.
    static let largeDocumentThreshold = 2_000_000

    @ObservationIgnored let textStorage = NSTextStorage()
    @ObservationIgnored private var storageObserver: StorageObserver?
    @ObservationIgnored private var derivedUpdate: Task<Void, Never>?

    var mode: Mode
    // Remembered for new windows. Settings are written only on a real change: SwiftUI re-sets these
    // bindings on every update, and an unconditional write would redraw every window in a loop.
    var sidebarTab: SidebarTab {
        didSet {
            if settings.sidebarTab != sidebarTab.rawValue { settings.sidebarTab = sidebarTab.rawValue }
        }
    }
    var sidebarVisibility: NavigationSplitViewVisibility {
        didSet {
            let visible = sidebarVisibility != .detailOnly
            if settings.sidebarVisible != visible { settings.sidebarVisible = visible }
        }
    }
    /// The folder shown in the Files sidebar. Kept here, not in the view, so it survives hiding the sidebar
    /// and can be handed to files opened from it.
    var browsedFolder: URL? {
        didSet {
            guard browsedFolder?.standardizedFileURL != oldValue?.standardizedFileURL else { return }
            fileTree = browsedFolder.map { FileNode(url: $0, isDirectory: true) }
            expandedFolders = []
            selectedFolder = nil
            revealInFiles()
            // Files created, renamed or deleted anywhere (here, Finder, git) show up in the list.
            folderWatcher = browsedFolder.map { folder in
                FolderWatcher(folder: folder) { [weak self] changed in self?.fileTree?.refreshLoaded(changed) }
            }
        }
    }
    private(set) var fileTree: FileNode?
    @ObservationIgnored private var folderWatcher: FolderWatcher?
    /// Folders open in the Files sidebar, as `FileNavigation.realPath`s.
    var expandedFolders: Set<String> = []
    /// The folder last clicked in the Files sidebar: New File creates there.
    var selectedFolder: URL?
    /// The file the Files sidebar scrolls to (the current one, once revealed).
    private(set) var filesScrollTarget: URL?
    /// A section to show once the document can show it (a link to `file.md#section` opened the file). Only for
    /// the text as loaded: the first edit drops it, so the caret never jumps while you type.
    @ObservationIgnored var pendingAnchor: String?
    /// The outline matches the loaded text (it is computed shortly after loading).
    @ObservationIgnored private var hasOutline = false
    @ObservationIgnored private let settings: AppSettings
    var isFocusMode: Bool
    var isTypewriterMode: Bool
    var fileURL: URL? {
        didSet {
            guard fileURL != oldValue else { return }
            revealInFiles()
        }
    }
    private(set) var outline: [OutlineItem] = []
    private(set) var stats = DocumentStats(text: "")
    /// 1-based caret position.
    /// The Vim mode line ("NORMAL", "INSERT", …), or nil when Vim mode is off.
    var vimStatus: String?
    var caretLine = 1
    /// The first source line visible in Read mode, as last reported by the reader.
    var readerTopLine: Int?
    var caretColumn = 1
    /// Incremented on every character edit; lets views know their snapshot is stale.
    private(set) var revision = 0
    private(set) var isLargeDocument = false

    /// Set by the editor and reader so commands can be routed to whichever is visible.
    @ObservationIgnored weak var editor: MarkdownTextView? {
        didSet { revealPendingAnchorInEditor() }
    }
    /// Created the first time Read mode is shown, then kept for instant switching.
    @ObservationIgnored private(set) var reader: ReaderController?

    func makeReaderIfNeeded() -> ReaderController {
        if let reader { return reader }
        let controller = ReaderController(model: self)
        reader = controller
        return controller
    }

    init(settings: AppSettings = .shared) {
        self.settings = settings
        mode = settings.openInReadMode ? .read : .edit
        sidebarTab = SidebarTab(rawValue: settings.sidebarTab) ?? .outline
        sidebarVisibility = settings.sidebarVisible ? .all : .detailOnly
        isFocusMode = settings.focusModeByDefault
        isTypewriterMode = settings.typewriterModeByDefault
        storageObserver = StorageObserver { [weak self] in self?.textDidChange() }
        textStorage.delegate = storageObserver
    }

    var text: String { textStorage.string }

    /// Replaces the whole text (used when loading or reverting), keeping the caret if possible.
    func replaceText(_ newText: String) {
        let selection = editor?.selectedRange()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: newText)
        if let selection, let editor {
            let location = min(selection.location, textStorage.length)
            editor.setSelectedRange(NSRange(location: location, length: 0))
        }
        editor?.undoManager?.removeAllActions()
    }

    func toggleFocusMode() {
        isFocusMode.toggle()
        HUD.shared.show(isFocusMode ? "Focus Mode On: other paragraphs are dimmed" : "Focus Mode Off")
    }

    func toggleTypewriterMode() {
        isTypewriterMode.toggle()
        HUD.shared.show(
            isTypewriterMode ? "Typewriter Mode On: the line you type stays centered" : "Typewriter Mode Off")
    }

    func toggleMode() {
        let line = mode == .edit ? editor?.topVisibleLine() : nil
        mode = mode == .edit ? .read : .edit
        switch mode {
        case .read:
            let reader = makeReaderIfNeeded()
            if let line { reader.pendingLine = line }
            // The hidden editor must never receive keystrokes (they would silently edit the file).
            editor?.window?.makeFirstResponder(reader.webView)
        case .edit:
            if let line = reader?.lastTopLine { editor?.scroll(toLine: line, select: false) }
            if let editor { editor.window?.makeFirstResponder(editor) }
        }
    }

    /// Jumps to an outline item in whichever mode is active.
    func reveal(_ item: OutlineItem) {
        switch mode {
        case .edit: editor?.scroll(toLine: item.line, select: true)
        case .read: reader?.scroll(toAnchor: item.slug)
        }
    }

    /// Opens the Files sidebar's folders down to the current file and scrolls to it, so a file opened from a
    /// link or another folder is always in view.
    func revealInFiles() {
        guard let root = browsedFolder, let file = fileURL else { return }
        expandedFolders.formUnion(FileNavigation.folderPaths(from: root, to: file))
        filesScrollTarget = file
    }

    /// Where New File creates: the folder clicked in the Files sidebar, otherwise the current file's folder,
    /// otherwise the browsed folder.
    var currentFolder: URL? {
        if let selectedFolder { return selectedFolder }
        if let file = fileURL, browsedFolder.map({ FileNavigation.isInside(file, folder: $0) }) ?? true {
            return file.deletingLastPathComponent()
        }
        return browsedFolder
    }

    /// Keeps the sidebar's open and selected folders after a folder moved. `oldPath` is its `realPath` from
    /// before the move (a path that no longer exists can't be resolved).
    func folderDidMove(from oldPath: String, to new: URL) {
        let newPath = FileNavigation.realPath(new)
        expandedFolders = Set(
            expandedFolders.map { path in
                path == oldPath || path.hasPrefix(oldPath + "/") ? newPath + path.dropFirst(oldPath.count) : path
            })
        // The selected folder may be the one that moved: resolve its parent, which still exists.
        if let selected = selectedFolder,
            FileNavigation.realPath(selected.deletingLastPathComponent()) + "/" + selected.lastPathComponent == oldPath
        {
            selectedFolder = new
        }
    }

    /// Shows the section with this anchor (a heading's slug), now or once the document has been laid out.
    func reveal(anchor: String) {
        switch mode {
        case .edit:
            pendingAnchor = anchor
            revealPendingAnchorInEditor()
        case .read:
            if let reader, reader.isLoaded { reader.scroll(toAnchor: anchor) } else { pendingAnchor = anchor }
        }
    }

    /// Edit mode needs both the outline (to find the heading's line) and the editor; whichever comes last
    /// shows the section, after the editor's first layout.
    private func revealPendingAnchorInEditor() {
        guard mode == .edit, hasOutline, editor != nil, let anchor = pendingAnchor else { return }
        pendingAnchor = nil
        guard let item = outline.first(where: { $0.slug == anchor }) else { return }
        Task { @MainActor [weak self] in self?.editor?.scroll(toLine: item.line, select: true) }
    }

    var isSidebarVisible: Bool { sidebarVisibility != .detailOnly }

    func toggleSidebar() {
        sidebarVisibility = isSidebarVisible ? .detailOnly : .all
    }

    func showSidebar(_ tab: SidebarTab) {
        if sidebarTab == tab, sidebarVisibility != .detailOnly {
            sidebarVisibility = .detailOnly
        } else {
            sidebarTab = tab
            sidebarVisibility = .all
        }
    }

    private func textDidChange() {
        revision += 1
        // Loading the text is the first change; any later one is an edit.
        if revision > 1 { pendingAnchor = nil }
        editor?.textStorageDidChangeCharacters()
        isLargeDocument = textStorage.length > Self.largeDocumentThreshold
        derivedUpdate?.cancel()
        let text = textStorage.string
        let delay: Duration = revision == 1 ? .zero : .milliseconds(250)
        derivedUpdate = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let (outline, stats) = await Task.detached(priority: .utility) {
                (Outline.items(for: text), DocumentStats(text: text))
            }.value
            guard !Task.isCancelled, let self else { return }
            self.outline = outline
            self.stats = stats
            self.hasOutline = true
            self.revealPendingAnchorInEditor()
        }
    }
}

/// Forwards character edits (not attribute-only styling passes) from the text storage.
@MainActor
private final class StorageObserver: NSObject, @preconcurrency NSTextStorageDelegate {
    let onCharactersEdited: @MainActor () -> Void

    init(onCharactersEdited: @escaping @MainActor () -> Void) {
        self.onCharactersEdited = onCharactersEdited
    }

    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        onCharactersEdited()
    }
}
