import Foundation
import MacMDKit
import Testing

@testable import MacMD

/// The Files sidebar's tree follows the disk.
@MainActor
struct FileTreeTests {
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "tree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: true)
        try write("a.md")
        try write("sub/inner.md")
    }

    private func write(_ path: String) throws {
        try "# \(path)".write(to: folder.appending(path: path), atomically: true, encoding: .utf8)
    }

    private func names(_ node: FileNode) -> [String] { node.children.map(\.name) }

    @Test func refreshPicksUpCreatedRenamedAndDeletedFiles() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = FileNode(url: folder, isDirectory: true)
        #expect(names(root) == ["sub", "a.md"])

        try write("b.md")
        try write("notes.txt")  // not Markdown: never listed
        try FileManager.default.moveItem(at: folder.appending(path: "a.md"), to: folder.appending(path: "z.md"))
        root.refreshLoaded()
        #expect(names(root) == ["sub", "b.md", "z.md"])

        try FileManager.default.removeItem(at: folder.appending(path: "b.md"))
        root.refreshLoaded()
        #expect(names(root) == ["sub", "z.md"])
    }

    @Test func refreshKeepsNodesAndOnlyReadsOpenedFolders() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = FileNode(url: folder, isDirectory: true)
        let sub = try #require(root.children.first { $0.name == "sub" })
        try write("b.md")
        root.refreshLoaded()
        #expect(root.children.first { $0.name == "sub" } === sub, "a folder keeps its node, so it stays open")

        _ = sub.children
        try write("sub/second.md")
        root.refreshLoaded()
        #expect(names(sub) == ["inner.md", "second.md"], "opened subfolders refresh too")
    }

    @Test func refreshOnlyRereadsChangedFolders() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = FileNode(url: folder, isDirectory: true)
        let sub = try #require(root.children.first { $0.name == "sub" })
        _ = sub.children
        try write("b.md")
        try write("sub/second.md")
        root.refreshLoaded([FileNavigation.realPath(folder.appending(path: "sub"))])
        #expect(names(sub) == ["inner.md", "second.md"], "the changed folder is re-read")
        #expect(names(root) == ["sub", "a.md"], "folders that didn't change are left alone")
    }

    @Test func refreshReplacesAFileThatBecameAFolder() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = FileNode(url: folder, isDirectory: true)
        try write("x.md")
        root.refreshLoaded()
        try FileManager.default.removeItem(at: folder.appending(path: "x.md"))
        try FileManager.default.createDirectory(at: folder.appending(path: "x.md"), withIntermediateDirectories: false)
        root.refreshLoaded()
        #expect(root.children.first { $0.name == "x.md" }?.isDirectory == true)
    }

    @Test func watcherReportsTheChangedFolder() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        var reported: [Set<String>?] = []
        let watcher = FolderWatcher(folder: folder, latency: 0.05) { reported.append($0) }
        try await Task.sleep(for: .milliseconds(500))
        reported = []  // only what happens from here on counts
        try write("sub/new.md")
        let sub = FileNavigation.realPath(folder.appending(path: "sub"))
        for _ in 0..<60 where !reported.contains(where: { $0?.contains(sub) ?? true }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reported.contains { $0?.contains(sub) ?? true }, "the subfolder is reported: \(reported)")
        withExtendedLifetime(watcher) {}
    }
}
