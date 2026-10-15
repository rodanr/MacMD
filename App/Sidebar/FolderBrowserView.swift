import AppKit
import SwiftUI

/// A lazily loaded tree of Markdown files around the current document.
struct FolderBrowserView: View {
    let model: DocumentModel
    @State private var root: FileNode?
    @Environment(\.zoom) private var zoom

    var body: some View {
        Group {
            if let root {
                List {
                    FileNodeChildren(node: root, currentFile: model.fileURL)
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
        .onAppear {
            if root == nil, let directory = model.fileURL?.deletingLastPathComponent() {
                root = FileNode(url: directory, isDirectory: true)
            }
        }
    }

    private func footer(for root: FileNode) -> some View {
        HStack {
            Label(root.name, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
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
            root = FileNode(url: url, isDirectory: true)
        }
    }
}

private struct FileNodeChildren: View {
    let node: FileNode
    let currentFile: URL?

    var body: some View {
        ForEach(node.children) { child in
            if child.isDirectory {
                DisclosureGroup {
                    FileNodeChildren(node: child, currentFile: currentFile)
                } label: {
                    Label(child.name, systemImage: "folder")
                }
            } else {
                Button {
                    LinkRouter.openFile(child.url)
                } label: {
                    Label(child.name, systemImage: "doc.text")
                        .foregroundStyle(
                            child.url.standardizedFileURL == currentFile?.standardizedFileURL
                                ? Color.accentColor : .primary
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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

    @ObservationIgnored private var loadedChildren: [FileNode]?

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var children: [FileNode] {
        if let loadedChildren { return loadedChildren }
        let loaded = Self.load(url)
        loadedChildren = loaded
        return loaded
    }

    private static func load(_ url: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]))
            ?? []
        return contents.compactMap { item in
            let isDirectory = (try? item.resourceValues(forKeys: Set(keys)).isDirectory) ?? false
            guard isDirectory || LinkRouter.markdownExtensions.contains(item.pathExtension.lowercased()) else {
                return nil
            }
            return FileNode(url: item, isDirectory: isDirectory)
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
