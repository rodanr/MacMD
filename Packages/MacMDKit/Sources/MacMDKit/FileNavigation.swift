import Foundation

/// Markdown files by extension.
public enum MarkdownFile {
    public static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]

    public static func isMarkdown(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

/// Where a document opened from another one (a link, the Files sidebar) should browse.
public enum FileNavigation {
    /// The browsed folder stays when the file is inside it, so moving between files never loses your place;
    /// a file elsewhere browses its own folder.
    public static func folderToBrowse(opening file: URL, from browsed: URL?) -> URL {
        if let browsed, isInside(file, folder: browsed) { return browsed }
        return file.deletingLastPathComponent()
    }

    /// Whether `url` is somewhere below `folder`. Compares whole path components after resolving `..` and
    /// symlinks, so `/var/x` is inside `/private/var` and `docs-old/x` is not inside `docs`.
    public static func isInside(_ url: URL, folder: URL) -> Bool {
        let path = canonicalComponents(url)
        let parent = canonicalComponents(folder)
        return path.count > parent.count && Array(path.prefix(parent.count)) == parent
    }

    /// Splits `notes.md#setup` into the file and its decoded section, if any.
    public static func splitFragment(_ url: URL) -> (file: URL, fragment: String?) {
        let fragment = url.fragment(percentEncoded: false).flatMap { $0.isEmpty ? nil : $0 }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return (url, fragment) }
        components.fragment = nil
        return (components.url ?? url, fragment)
    }

    /// The folders to expand so `file` shows in a tree rooted at `root`: each folder below the root down to the
    /// file's own, top first, as `realPath`s. Empty when the file is directly in the root or outside it.
    public static func folderPaths(from root: URL, to file: URL) -> [String] {
        let rootPath = realPath(root)
        let parent = realPath(file.deletingLastPathComponent())
        guard parent.hasPrefix(rootPath + "/") else { return [] }
        var paths: [String] = []
        var current = rootPath
        for component in parent.dropFirst(rootPath.count + 1).split(separator: "/") {
            current += "/" + component
            paths.append(current)
        }
        return paths
    }

    /// The path as the file system reports it (FSEvents, for one): symlinks resolved, `/private/var` kept
    /// (Foundation's `resolvingSymlinksInPath()` turns it into `/var`), no trailing slash. A path that doesn't
    /// exist is only standardized.
    public static func realPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard let resolved = realpath(path, nil) else {
            return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func canonicalComponents(_ url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    }
}

/// Names for files created from the app.
public enum NewFileName {
    /// The file name for what the user typed: trimmed, with `.md` added unless it already has a Markdown
    /// extension. Nil for names that aren't a plain file in the folder (empty, hidden, containing `/` or `:`).
    public static func normalized(_ input: String) -> String? {
        var name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasSuffix(".") { name.removeLast() }  // "notes." means notes.md, not notes..md
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else { return nil }
        return MarkdownFile.isMarkdown(URL(filePath: name)) ? name : name + ".md"
    }

    /// A folder name: trimmed, never given an extension. Nil for empty, hidden, `/` or `:` names.
    public static func normalizedFolder(_ input: String) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else { return nil }
        return name
    }

    /// `name`, or `name 2`, `name 3`… when it's taken. APFS ignores case by default, so this does too.
    public static func unique(_ name: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        let url = URL(filePath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            number += 1
        }
    }
}
