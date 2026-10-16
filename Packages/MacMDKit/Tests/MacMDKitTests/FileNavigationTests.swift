import Foundation
import Testing

@testable import MacMDKit

@Suite struct FileNavigationTests {
    private let docs = URL(filePath: "/Users/a/docs", directoryHint: .isDirectory)

    @Test func keepsTheBrowsedFolderForFilesInsideIt() {
        let nested = URL(filePath: "/Users/a/docs/guide/setup.md")
        #expect(FileNavigation.folderToBrowse(opening: nested, from: docs).path == "/Users/a/docs")
        let sibling = URL(filePath: "/Users/a/docs/b.md")
        #expect(FileNavigation.folderToBrowse(opening: sibling, from: docs).path == "/Users/a/docs")
    }

    @Test func browsesTheFilesFolderWhenItIsOutside() {
        let outside = URL(filePath: "/Users/a/README.md")
        #expect(FileNavigation.folderToBrowse(opening: outside, from: docs).path == "/Users/a")
        #expect(FileNavigation.folderToBrowse(opening: outside, from: nil).path == "/Users/a")
    }

    @Test func resolvesDotDotBeforeComparing() {
        let viaParent = URL(filePath: "/Users/a/docs/guide/../b.md")
        #expect(FileNavigation.isInside(viaParent, folder: docs))
        let escaping = URL(filePath: "/Users/a/docs/../other/b.md")
        #expect(!FileNavigation.isInside(escaping, folder: docs))
    }

    @Test func aFolderNamePrefixIsNotInside() {
        #expect(!FileNavigation.isInside(URL(filePath: "/Users/a/docs-old/x.md"), folder: docs))
        #expect(!FileNavigation.isInside(docs, folder: docs), "a folder is not inside itself")
    }

    @Test func comparesThroughSymlinks() throws {
        // macOS keeps temporary files under /var, a symlink to /private/var.
        let folder = FileManager.default.temporaryDirectory.appending(path: "nav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "a.md")
        let resolvedFolder = folder.resolvingSymlinksInPath()
        #expect(FileNavigation.isInside(file, folder: resolvedFolder))
        #expect(FileNavigation.isInside(file.resolvingSymlinksInPath(), folder: folder))
    }

    @Test func realPathsMatchWhatTheFileSystemReports() throws {
        // FSEvents reports /private/var/…; Foundation's resolvingSymlinksInPath() strips /private.
        let folder = FileManager.default.temporaryDirectory.appending(path: "real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = FileNavigation.realPath(folder)
        #expect(real.hasPrefix("/private/"), "\(real)")
        #expect(FileNavigation.realPath(URL(filePath: real)) == real)
        #expect(!real.hasSuffix("/"))
        #expect(
            FileNavigation.realPath(URL(filePath: "/no/such/place/")) == "/no/such/place", "missing paths still work")
    }

    @Test func foldersToExpandForANestedFile() throws {
        let root = try temporaryTree(["guide/deep/setup.md", "top.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let real = FileNavigation.realPath(root)
        #expect(
            FileNavigation.folderPaths(from: root, to: root.appending(path: "guide/deep/setup.md"))
                == [real + "/guide", real + "/guide/deep"])
        #expect(FileNavigation.folderPaths(from: root, to: root.appending(path: "top.md")).isEmpty)
        #expect(
            FileNavigation.folderPaths(from: root.appending(path: "guide"), to: root.appending(path: "top.md")).isEmpty)
        #expect(FileNavigation.folderPaths(from: root, to: root).isEmpty)
    }

    private func temporaryTree(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "tree-\(UUID().uuidString)")
        for file in files {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return root
    }

    @Test func splitsTheSectionFromALink() throws {
        let link = try #require(URL(string: "file:///Users/a/docs/my%20notes.md#getting-started"))
        let (file, fragment) = FileNavigation.splitFragment(link)
        #expect(file.path == "/Users/a/docs/my notes.md")
        #expect(file.fragment == nil)
        #expect(fragment == "getting-started")
    }

    @Test func decodesTheSectionAndIgnoresAnEmptyOne() throws {
        let encoded = try #require(URL(string: "file:///a/b.md#caf%C3%A9"))
        #expect(FileNavigation.splitFragment(encoded).fragment == "café")
        let empty = try #require(URL(string: "file:///a/b.md#"))
        #expect(FileNavigation.splitFragment(empty).fragment == nil)
        #expect(FileNavigation.splitFragment(URL(filePath: "/a/b.md")).fragment == nil)
    }

    @Test func recognisesMarkdownFiles() {
        #expect(MarkdownFile.isMarkdown(URL(filePath: "/a/B.MD")))
        #expect(MarkdownFile.isMarkdown(URL(filePath: "/a/b.markdown")))
        #expect(!MarkdownFile.isMarkdown(URL(filePath: "/a/b.txt")))
    }
}

@Suite struct NewFileNameTests {
    @Test func addsTheMarkdownExtension() {
        #expect(NewFileName.normalized("notes") == "notes.md")
        #expect(NewFileName.normalized("  Meeting notes  ") == "Meeting notes.md")
        #expect(NewFileName.normalized("v1.2 plan") == "v1.2 plan.md")
        #expect(NewFileName.normalized("notes.") == "notes.md")
    }

    @Test func keepsAMarkdownExtension() {
        #expect(NewFileName.normalized("notes.md") == "notes.md")
        #expect(NewFileName.normalized("notes.markdown") == "notes.markdown")
        #expect(NewFileName.normalized("Notes.MD") == "Notes.MD")
    }

    @Test func rejectsNamesThatAreNotAFileInThisFolder() {
        for bad in ["", "   ", ".md", ".hidden", "a/b", "../up", "a:b", "."] {
            #expect(NewFileName.normalized(bad) == nil, "\(bad) is rejected")
        }
    }

    @Test func folderNamesGetNoExtension() {
        #expect(NewFileName.normalizedFolder(" drafts ") == "drafts")
        #expect(NewFileName.normalizedFolder("v1.2") == "v1.2")
        for bad in ["", " ", ".git", "a/b", "a:b", ".", ".."] {
            #expect(NewFileName.normalizedFolder(bad) == nil, "\(bad) is rejected")
        }
    }

    @Test func picksAFreeName() {
        #expect(NewFileName.unique("Untitled.md", existing: []) == "Untitled.md")
        #expect(NewFileName.unique("Untitled.md", existing: ["Untitled.md"]) == "Untitled 2.md")
        #expect(NewFileName.unique("Untitled.md", existing: ["untitled.md", "Untitled 2.md"]) == "Untitled 3.md")
        #expect(NewFileName.unique("a.b.md", existing: ["a.b.md"]) == "a.b 2.md")
    }
}
