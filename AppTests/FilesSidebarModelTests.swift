import Foundation
import MacMDKit
import Testing

@testable import MacMD

/// Which folders the Files sidebar opens, and where New File creates. Serialized: open folders are one
/// memory shared by every document.
@MainActor @Suite(.serialized)
struct FilesSidebarModelTests {
    private let root: URL

    init() throws {
        FolderMemory.shared.expanded = []
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
        #expect(model.expandedFolders.isSuperset(of: [path("guide"), path("guide/deep")]))
        #expect(!model.expandedFolders.contains(path("docs")))
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
        #expect(!model.expandedFolders.contains(path("guide")), "nothing outside the folder is opened")
    }

    @Test func openFoldersAreSharedByEveryDocument() {
        defer { try? FileManager.default.removeItem(at: root) }
        let first = DocumentModel()
        first.browsedFolder = root
        first.fileURL = root.appending(path: "guide/deep/setup.md")
        let second = DocumentModel()
        second.browsedFolder = root
        second.fileURL = root.appending(path: "index.md")
        #expect(second.expandedFolders.contains(path("guide/deep")), "another tab shows the same open folders")
        second.expandedFolders.remove(path("guide/deep"))
        #expect(!first.expandedFolders.contains(path("guide/deep")), "and closing one closes it everywhere")
    }

    @Test func aFormerRootStaysOpenUnderItsParent() {
        defer { try? FileManager.default.removeItem(at: root) }
        let inGuide = DocumentModel()
        inGuide.browsedFolder = root.appending(path: "guide/deep")
        inGuide.fileURL = root.appending(path: "guide/deep/setup.md")
        // A link to a file further up browses the parent: the folder you were in stays open.
        let atTop = DocumentModel()
        atTop.browsedFolder = root
        atTop.fileURL = root.appending(path: "index.md")
        #expect(atTop.expandedFolders.contains(path("guide/deep")))
    }

    @Test func changingTheRootKeepsOpenFolders() {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = DocumentModel()
        model.browsedFolder = root
        model.fileURL = root.appending(path: "guide/deep/setup.md")
        model.browsedFolder = root.appending(path: "docs")
        model.browsedFolder = root
        #expect(model.expandedFolders.isSuperset(of: [path("guide"), path("guide/deep")]))
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
        #expect(model.expandedFolders.isSuperset(of: [path("manual"), path("manual/deep")]))
        #expect(!model.expandedFolders.contains(oldPath))
        #expect(model.selectedFolder == renamed)
    }

    @Test func theMarkdownIndexFollowsTheDisk() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "src/main.swift"))
        let model = DocumentModel()
        model.browsedFolder = root
        for _ in 0..<60 where model.markdownIndex == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(model.markdownIndex?.hasMarkdown(inFolderAt: path("docs")) == true)
        #expect(model.markdownIndex?.hasMarkdown(inFolderAt: path("src")) == false)

        try Data().write(to: root.appending(path: "src/notes.md"))
        for _ in 0..<60 where model.markdownIndex?.hasMarkdown(inFolderAt: path("src")) != true {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.markdownIndex?.hasMarkdown(inFolderAt: path("src")) == true, "a new file is picked up")
    }
}
