import Foundation

/// The Markdown files below a folder, for the Files sidebar: which folders hold Markdown (so the others can be
/// quieter) and a filter by name. Built off the main thread; dependency and build folders are skipped.
public struct MarkdownIndex: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let url: URL
        /// The path below the root, such as `docs/setup.md`.
        public let relativePath: String
    }

    /// Folders that hold generated or third-party files, never the project's own documents.
    public static let skippedFolders: Set<String> = [
        "node_modules", ".build", "build", "DerivedData", "Pods", "Carthage", "target", "dist", "vendor", "venv",
        "__pycache__",
    ]

    /// Markdown files, sorted by path.
    public let entries: [Entry]
    /// False when the scan stopped at its limit: folders it didn't reach are unknown.
    public let isComplete: Bool
    /// `FileNavigation.realPath`s of every folder with Markdown at any depth (the root included).
    private let foldersWithMarkdown: Set<String>

    /// Walks `root`, stopping after `limit` items so a huge folder never stalls.
    public static func scan(root: URL, limit: Int = 20_000) -> MarkdownIndex {
        let rootComponents = root.standardizedFileURL.pathComponents
        let rootPath = FileNavigation.realPath(root)
        var entries: [Entry] = []
        var folders: Set<String> = []
        var visited = 0
        var isComplete = true
        let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = enumerator?.nextObject() as? URL {
            visited += 1
            if visited > limit {
                isComplete = false
                break
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skippedFolders.contains(url.lastPathComponent) { enumerator?.skipDescendants() }
                continue
            }
            guard MarkdownFile.isMarkdown(url) else { continue }
            let components = Array(url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count))
            entries.append(Entry(url: url, relativePath: components.joined(separator: "/")))
            var folder = rootPath
            folders.insert(folder)
            for component in components.dropLast() {
                folder += "/" + component
                folders.insert(folder)
            }
        }
        entries.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return MarkdownIndex(entries: entries, isComplete: isComplete, foldersWithMarkdown: folders)
    }

    /// Whether the folder (a `FileNavigation.realPath`) holds Markdown at any depth; nil when the scan didn't
    /// finish and found none there, since it may not have looked.
    public func hasMarkdown(inFolderAt path: String) -> Bool? {
        if foldersWithMarkdown.contains(path) { return true }
        return isComplete ? false : nil
    }

    /// Files whose path contains every word of `query`, ignoring case and accents. Names that start with the
    /// query come first, then names containing it, then matches in the folder path only.
    public func matches(_ query: String, limit: Int = 200) -> [Entry] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: options, locale: nil)
        let words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var ranked: [(rank: Int, entry: Entry)] = []
        for entry in entries {
            let path = entry.relativePath.folding(options: options, locale: nil)
            guard words.allSatisfy({ path.contains($0) }) else { continue }
            let name = (path as NSString).lastPathComponent
            let rank = name.hasPrefix(phrase) ? 0 : name.contains(phrase) ? 1 : 2
            ranked.append((rank, entry))
        }
        // `entries` is sorted by path, and a stable sort keeps that order within a rank.
        return ranked.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .prefix(limit)
            .map(\.element.entry)
    }
}
