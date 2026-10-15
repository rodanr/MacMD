import Foundation

/// Relative file paths for links inserted into documents.
public enum RelativePath {
    /// The path of `target` relative to the directory `base`.
    public static func from(_ base: URL, to target: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        var common = 0
        while common < min(baseComponents.count, targetComponents.count),
            baseComponents[common] == targetComponents[common]
        {
            common += 1
        }
        let ups = Array(repeating: "..", count: baseComponents.count - common)
        return (ups + targetComponents[common...]).joined(separator: "/")
    }

    /// Wraps destinations containing spaces in `<…>` as CommonMark requires.
    public static func markdownEscaped(_ path: String) -> String {
        path.contains(where: { $0 == " " || $0 == "(" || $0 == ")" }) ? "<\(path)>" : path
    }
}
