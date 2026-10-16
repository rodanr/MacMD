import Foundation
import Testing

@testable import MacMDKit

@Suite struct MarkdownIndexTests {
    /// A code-like folder: Markdown in a few places, lots of folders without any.
    private func makeRepo(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "repo-\(UUID().uuidString)")
        for file in files {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return root
    }

    private func relative(_ index: MarkdownIndex) -> [String] { index.entries.map(\.relativePath) }

    @Test func findsMarkdownAndMarksEveryFolderAboveIt() throws {
        let root = try makeRepo(["README.md", "docs/api/v1/auth.md", "src/main.swift", "src/util/helpers.swift"])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = MarkdownIndex.scan(root: root)
        #expect(relative(index) == ["docs/api/v1/auth.md", "README.md"])
        #expect(index.isComplete)
        let real = FileNavigation.realPath(root)
        #expect(index.hasMarkdown(inFolderAt: real) == true)
        #expect(index.hasMarkdown(inFolderAt: real + "/docs") == true)
        #expect(index.hasMarkdown(inFolderAt: real + "/docs/api/v1") == true)
        #expect(index.hasMarkdown(inFolderAt: real + "/src") == false)
        #expect(index.hasMarkdown(inFolderAt: real + "/src/util") == false)
    }

    @Test func skipsDependencyBuildAndHiddenFolders() throws {
        let root = try makeRepo([
            "docs/a.md", "node_modules/pkg/readme.md", "build/out.md", ".git/notes.md", "Pods/x/README.md",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = MarkdownIndex.scan(root: root)
        #expect(relative(index) == ["docs/a.md"])
        #expect(index.hasMarkdown(inFolderAt: FileNavigation.realPath(root) + "/node_modules") == false)
    }

    @Test func aScanThatHitsTheLimitDoesNotClaimFoldersAreEmpty() throws {
        let root = try makeRepo((1...30).map { "src/file\($0).swift" } + ["zdocs/late.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = MarkdownIndex.scan(root: root, limit: 10)
        #expect(!index.isComplete)
        #expect(index.hasMarkdown(inFolderAt: FileNavigation.realPath(root) + "/src") == nil, "unknown, not false")
    }

    @Test func matchesRankFileNamesFirst() throws {
        let root = try makeRepo([
            "setup.md", "docs/setup-guide.md", "docs/install.md", "setup/notes.md", "guides/Résumé setup.md",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = MarkdownIndex.scan(root: root)
        let names = index.matches("setup").map(\.relativePath)
        #expect(names.prefix(2) == ["docs/setup-guide.md", "setup.md"], "names starting with the query first")
        #expect(names.contains("guides/Résumé setup.md"), "then names containing it")
        #expect(names.last == "setup/notes.md", "then a match in the folder path only")
        #expect(!names.contains("docs/install.md"))
    }

    @Test func matchesIgnoreCaseAccentsAndWordOrder() throws {
        let root = try makeRepo(["guides/Résumé setup.md", "docs/api/auth.md", "docs/other.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let index = MarkdownIndex.scan(root: root)
        #expect(index.matches("RESUME").map(\.relativePath) == ["guides/Résumé setup.md"])
        #expect(index.matches("auth docs").map(\.relativePath) == ["docs/api/auth.md"], "every word, any order")
        #expect(index.matches("  ").isEmpty)
        #expect(index.matches("zzz").isEmpty)
    }

    @Test func matchesAreCapped() throws {
        let root = try makeRepo((1...30).map { "notes/n\($0).md" })
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(MarkdownIndex.scan(root: root).matches("n", limit: 5).count == 5)
    }
}
