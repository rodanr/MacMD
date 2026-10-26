import AppKit
import MacMDKit
import SwiftUI

/// A lazily loaded tree of Markdown files around the current document.
struct FolderBrowserView: View {
    let model: DocumentModel
    @Environment(\.zoom) private var zoom
    /// The Files filter; per window and never saved.
    @State private var query = ""
    /// The list has been scrolled to the current file (or has nothing to scroll to).
    @State private var isPositioned = false

    var body: some View {
        Group {
            if let root = model.fileTree {
                ScrollViewReader { proxy in
                    Group {
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            List {
                                FileNodeChildren(node: root, model: model, currentPath: currentPath)
                            }
                        } else {
                            FilterResults(query: query, model: model, currentPath: currentPath)
                        }
                    }
                    .listStyle(.sidebar)
                    .font(.system(size: 13 * zoom))
                    // Rows scroll under the filter and footer: they need their own backing, or the rows show through.
                    .safeAreaInset(edge: .top, spacing: 0) {
                        FilterField(query: $query)
                            .background(.bar)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        footer(for: root)
                            .background(.bar)
                    }
                    // A new window starts at the top: stay hidden until it has scrolled to the current file.
                    .opacity(isPositioned ? 1 : 0)
                    .onAppear { scroll(proxy) }
                    .onChange(of: model.filesScrollTarget) { scroll(proxy) }
                }
            } else {
                ContentUnavailableView {
                    Label("No Folder", systemImage: "folder")
                } description: {
                    Text("Save the document or choose a folder to browse its Markdown files.")
                } actions: {
                    Button("Choose Folder…", action: chooseFolder)
                }
            }
        }
        .onAppear(perform: browseDocumentFolderIfNeeded)
        .onChange(of: model.fileURL) { browseDocumentFolderIfNeeded() }
    }

    private var currentPath: String? { model.fileURL.map(FileNavigation.realPath) }

    /// Keeps the current file in view once its folders are open (rows only exist once their folder is).
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let target = model.filesScrollTarget else {
            isPositioned = true
            return
        }
        let id = FileNavigation.realPath(target)
        Task { @MainActor in
            proxy.scrollTo(id, anchor: .center)
            isPositioned = true
        }
    }

    /// Without a chosen folder, browse the one the document is in (once it has been saved).
    private func browseDocumentFolderIfNeeded() {
        if model.browsedFolder == nil, let directory = model.fileURL?.deletingLastPathComponent() {
            model.browsedFolder = directory
        }
    }

    private func footer(for root: FileNode) -> some View {
        let target = model.currentFolder ?? root.url
        let isRoot = FileNavigation.realPath(target) == root.path
        return HStack {
            Label(isRoot ? root.name : "\(root.name) › \(target.lastPathComponent)", systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                FileActions.newFile(in: target, model: model)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New File in “\(target.lastPathComponent)”…")
            .accessibilityLabel("New File")
            Button(action: chooseFolder) { Image(systemName: "folder.badge.plus") }
                .buttonStyle(.borderless)
                .help("Choose Folder…")
        }
        .font(.system(size: 12 * zoom))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Browse"
        if panel.runModal() == .OK, let url = panel.url {
            model.browsedFolder = url
        }
    }
}

private struct FileNodeChildren: View {
    let node: FileNode
    let model: DocumentModel
    /// The current file's `realPath`, highlighted in the list.
    let currentPath: String?
    @Environment(\.zoom) private var zoom

    var body: some View {
        ForEach(orderedChildren) { child in
            if child.isDirectory {
                DisclosureGroup(isExpanded: expansion(of: child)) {
                    FileNodeChildren(node: child, model: model, currentPath: currentPath)
                } label: {
                    FolderRow(node: child, model: model, isExpanded: expansion(of: child), isQuiet: isQuiet(child))
                }
            } else {
                let isCurrent = child.path == currentPath
                Button {
                    model.selectedFolder = nil
                    LinkRouter.openFile(child.url, browsing: model.browsedFolder)
                } label: {
                    FileLabel(name: child.name, systemImage: "doc.text")
                        .padding(.vertical, 2 * zoom)
                        .padding(.horizontal, 6 * zoom)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SelectionPill(isSelected: isCurrent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .contextMenu { RowMenu(url: child.url, isDirectory: false, model: model) }
            }
        }
    }

    /// Folders with Markdown first, then files, then folders without any, which are listed but quiet.
    private var orderedChildren: [FileNode] {
        let children = node.children
        guard model.markdownIndex != nil else { return children }
        let folders = children.filter(\.isDirectory)
        return folders.filter { !isQuiet($0) } + children.filter { !$0.isDirectory } + folders.filter(isQuiet)
    }

    /// Known to hold no Markdown at any depth (never a guess: an unfinished scan quiets nothing).
    private func isQuiet(_ folder: FileNode) -> Bool {
        model.markdownIndex?.hasMarkdown(inFolderAt: folder.path) == false
    }

    private func expansion(of folder: FileNode) -> Binding<Bool> {
        Binding(
            get: { model.expandedFolders.contains(folder.path) },
            set: { open in
                if open { model.expandedFolders.insert(folder.path) } else { model.expandedFolders.remove(folder.path) }
            })
    }
}

/// A folder's name: clicking selects it (New File creates there) and opens it. A folder without Markdown is
/// quiet: secondary text, but just as usable.
private struct FolderRow: View {
    let node: FileNode
    let model: DocumentModel
    @Binding var isExpanded: Bool
    let isQuiet: Bool
    @Environment(\.zoom) private var zoom

    var body: some View {
        let isSelected = model.selectedFolder.map(FileNavigation.realPath) == node.path
        Button {
            // The first click opens a closed folder; clicking the selected folder again closes it.
            if isSelected || !isExpanded { isExpanded.toggle() }
            model.selectedFolder = node.url
        } label: {
            // The same insets as a file row's pill, so folder and file icons line up.
            FileLabel(name: node.name, systemImage: "folder", isQuiet: isQuiet)
                .padding(.vertical, 2 * zoom)
                .padding(.horizontal, 6 * zoom)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SelectionPill(isSelected: isSelected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isQuiet ? "No Markdown files yet. Right-click → New File… to add one." : "")
        .accessibilityValue(isQuiet ? "No Markdown files" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu { RowMenu(url: node.url, isDirectory: true, model: model) }
    }
}

/// The right-click menu of a file or folder row. New items go into the folder, or next to the file.
private struct RowMenu: View {
    let url: URL
    let isDirectory: Bool
    let model: DocumentModel

    var body: some View {
        let folder = isDirectory ? url : url.deletingLastPathComponent()
        Button("New File…") { FileActions.newFile(in: folder, model: model) }
        Button("New Folder…") { FileActions.newFolder(in: folder, model: model) }
        Divider()
        Button("Rename…") { FileActions.rename(url, isDirectory: isDirectory, model: model) }
        Button("Move to Trash") { FileActions.moveToTrash(url, isDirectory: isDirectory) }
        Divider()
        Button("Show in Finder") { FileActions.showInFinder(url) }
    }
}

/// The soft accent pill behind the current file or the selected folder.
private struct SelectionPill: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.panelRadius / 2)
            .fill(isSelected ? Color.accentColor.opacity(0.14) : .clear)
    }
}

/// A file or folder name in primary text, with a quieter icon.
private struct FileLabel: View {
    let name: String
    let systemImage: String
    var isQuiet = false

    var body: some View {
        Label {
            Text(name).foregroundStyle(isQuiet ? .secondary : .primary)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isQuiet ? .tertiary : .secondary)
        }
    }
}

/// The search field above the Files list. Esc clears it.
private struct FilterField: View {
    @Binding var query: String
    @Environment(\.zoom) private var zoom

    var body: some View {
        HStack(spacing: 4 * zoom) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter Markdown Files", text: $query)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("files-filter")
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear Filter")
            }
        }
        .font(.system(size: 12 * zoom))
        .padding(.horizontal, 8 * zoom)
        .padding(.vertical, 5 * zoom)
        .background(RoundedRectangle(cornerRadius: Theme.panelRadius / 2).fill(.quaternary.opacity(0.6)))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Markdown files matching the filter, from every folder, each with the folder it's in.
private struct FilterResults: View {
    let query: String
    let model: DocumentModel
    let currentPath: String?
    @Environment(\.zoom) private var zoom

    var body: some View {
        if let index = model.markdownIndex {
            let results = index.matches(query)
            List {
                ForEach(results, id: \.relativePath) { entry in
                    let isCurrent = FileNavigation.realPath(entry.url) == currentPath
                    let folder = (entry.relativePath as NSString).deletingLastPathComponent
                    Button {
                        model.selectedFolder = nil
                        LinkRouter.openFile(entry.url, browsing: model.browsedFolder)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            FileLabel(name: entry.url.lastPathComponent, systemImage: "doc.text")
                            if !folder.isEmpty {
                                Text(folder)
                                    .font(.system(size: 11 * zoom))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                    .padding(.leading, 22 * zoom)
                            }
                        }
                        .padding(.vertical, 2 * zoom)
                        .padding(.horizontal, 6 * zoom)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SelectionPill(isSelected: isCurrent))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.url.lastPathComponent)
                    .accessibilityValue(folder)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    .contextMenu { RowMenu(url: entry.url, isDirectory: false, model: model) }
                }
                if results.isEmpty {
                    Text("No Markdown files match “\(query)”.").foregroundStyle(.secondary)
                }
                if !index.isComplete {
                    Text("Searched the first 20,000 items.").font(.caption).foregroundStyle(.tertiary)
                }
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A file or folder; folder contents are read on first access.
@MainActor @Observable
final class FileNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    /// `FileNavigation.realPath(url)`: the row's identity, and what expansion and FSEvents use.
    nonisolated let path: String
    var name: String { url.lastPathComponent }
    nonisolated var id: String { path }

    // Loading happens while SwiftUI reads `children`, so the cache itself is not observed (writing observed
    // state during a view update would loop); `version` tells views when a refresh changed it.
    @ObservationIgnored private var loadedChildren: [FileNode]?
    private var version = 0

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
        path = FileNavigation.realPath(url)
    }

    var children: [FileNode] {
        _ = version
        if let loadedChildren { return loadedChildren }
        let loaded = Self.load(url)
        loadedChildren = loaded
        return loaded
    }

    /// Re-reads the folders that have been read (never the ones nobody opened), or only those in `changed`
    /// (`FileNavigation.realPath` form). Nodes that are still there are kept, so open folders stay open.
    func refreshLoaded(_ changed: Set<String>? = nil) {
        guard let old = loadedChildren else { return }
        guard changed == nil || changed?.contains(path) == true else {
            for child in old where child.isDirectory { child.refreshLoaded(changed) }
            return
        }
        let existing = Dictionary(old.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let fresh = Self.load(url).map { node in
            existing[node.path].flatMap { $0.isDirectory == node.isDirectory ? $0 : nil } ?? node
        }
        if fresh.map(ObjectIdentifier.init) != old.map(ObjectIdentifier.init) {
            loadedChildren = fresh
            version += 1
        }
        for child in fresh where child.isDirectory { child.refreshLoaded(changed) }
    }

    private static func load(_ url: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]))
            ?? []
        return contents.compactMap { item in
            let isDirectory = (try? item.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
            guard isDirectory || MarkdownFile.isMarkdown(item) else { return nil }
            return FileNode(url: item, isDirectory: isDirectory)
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
