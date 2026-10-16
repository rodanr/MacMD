import Foundation
import MacMDKit
import Testing

@testable import MacMD

/// Which folders the Files sidebar opens, and where New File creates.
@MainActor
struct FilesSidebarModelTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "files-\(UUID().uuidString)")
        for path in ["guide/deep/setup.md", "index.md", "docs/a.md"] {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
    }

    private func path(_ relative: String) -> String { FileNavigation.realPath(root.appending(path: relative)) }

    @Test func revealsTheFoldersDownToTheCurrentFile() {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DocumentModel()
        model.browsedFolder = root
        model.fileURL = root.appending(path: "guide/deep/setup.md")
        #expect(model.expandedFolders == [path("guide"), path("guide/deep")])
        #expect(model.filesScrollTarget == model.fileURL)
    }

    @Test func newFileGoesToTheSelectedFolderThenTheCurrentFilesFolderThenTheRoot() {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DocumentModel()
        model.browsedFolder = root
        #expect(model.currentFolder == root)
        model.fileURL = root.appending(path: "guide/deep/setup.md")
        #expect(model.currentFolder?.path() == root.appending(path: "guide/deep/").path())
        model.selectedFolder = root.appending(path: "docs")
        #expect(model.currentFolder == root.appending(path: "docs"))
    }

    @Test func aFileOutsideTheBrowsedFolderUsesTheBrowsedFolder() {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DocumentModel()
        model.browsedFolder = root.appending(path: "docs")
        model.fileURL = root.appending(path: "index.md")
        #expect(model.currentFolder == root.appending(path: "docs"))
        #expect(model.expandedFolders.isEmpty)
    }

    @Test func renamingAFolderKeepsItOpenAndSelected() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DocumentModel()
        model.browsedFolder = root
        model.fileURL = root.appending(path: "guide/deep/setup.md")
        model.selectedFolder = root.appending(path: "guide")
        let renamed = root.appending(path: "manual")
        let oldPath = path("guide")
        try FileManager.default.moveItem(at: root.appending(path: "guide"), to: renamed)
        model.folderDidMove(from: oldPath, to: renamed)
        #expect(model.expandedFolders == [path("manual"), path("manual/deep")])
        #expect(model.selectedFolder == renamed)
    }
}
