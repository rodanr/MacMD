import AppKit
import MacMDKit
import SwiftUI

/// A lazily loaded tree of Markdown files around the current document.
struct FolderBrowserView: View {
    let model: DocumentModel
    @Environment(\.zoom) private var zoom

    var body: some View {
        Group {
            if let root = model.fileTree {
                List {
                    FileNodeChildren(node: root, currentFile: model.fileURL, browsedFolder: model.browsedFolder)
                }
                .listStyle(.sidebar)
                .font(.system(size: 13 * zoom))
                .safeAreaInset(edge: .bottom) {
                    footer(for: root)
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

    /// Without a chosen folder, browse the one the document is in (once it has been saved).
    private func browseDocumentFolderIfNeeded() {
        if model.browsedFolder == nil, let directory = model.fileURL?.deletingLastPathComponent() {
            model.browsedFolder = directory
        }
    }

    private func footer(for root: FileNode) -> some View {
        HStack {
            Label(root.name, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                NewFile.create(in: root.url, browsing: root.url)
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("New File…")
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
    let currentFile: URL?
    let browsedFolder: URL?
    @Environment(\.zoom) private var zoom

    var body: some View {
        ForEach(node.children) { child in
            if child.isDirectory {
                DisclosureGroup {
                    FileNodeChildren(node: child, currentFile: currentFile, browsedFolder: browsedFolder)
                } label: {
                    // The same insets as a file row's pill, so folder and file icons line up.
                    FileLabel(name: child.name, systemImage: "folder")
                        .padding(.vertical, 2 * zoom)
                        .padding(.horizontal, 6 * zoom)
                        .contextMenu {
                            Button("New File…") { NewFile.create(in: child.url, browsing: browsedFolder) }
                            showInFinder(child.url)
                        }
                }
            } else {
                let isCurrent = child.url.standardizedFileURL == currentFile?.standardizedFileURL
                Button {
                    LinkRouter.openFile(child.url, browsing: browsedFolder)
                } label: {
                    FileLabel(name: child.name, systemImage: "doc.text")
                        .padding(.vertical, 2 * zoom)
                        .padding(.horizontal, 6 * zoom)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.panelRadius / 2)
                                .fill(isCurrent ? Color.accentColor.opacity(0.14) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .contextMenu {
                    Button("New File…") {
                        NewFile.create(in: child.url.deletingLastPathComponent(), browsing: browsedFolder)
                    }
                    showInFinder(child.url)
                }
            }
        }
    }

    private func showInFinder(_ url: URL) -> some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// A file or folder name in primary text, with a quieter icon.
private struct FileLabel: View {
    let name: String
    let systemImage: String

    var body: some View {
        Label {
            Text(name).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }
}

/// A file or folder; folder contents are read on first access.
@MainActor @Observable
final class FileNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
    nonisolated var id: URL { url }

    // Loading happens while SwiftUI reads `children`, so the cache itself is not observed (writing observed
    // state during a view update would loop); `version` tells views when a refresh changed it.
    @ObservationIgnored private var loadedChildren: [FileNode]?
    private var version = 0

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
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
        guard changed == nil || changed?.contains(FileNavigation.realPath(url)) == true else {
            for child in old where child.isDirectory { child.refreshLoaded(changed) }
            return
        }
        let existing = Dictionary(old.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        let fresh = Self.load(url).map { node in
            existing[node.url].flatMap { $0.isDirectory == node.isDirectory ? $0 : nil } ?? node
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
