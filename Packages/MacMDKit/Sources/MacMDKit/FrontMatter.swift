import Foundation

/// YAML front matter: a `---` line at the very start of a file, closed by a `---` or `...` line, as used by Jekyll,
/// Hugo, Obsidian and Astro. Markdown itself would read it as a horizontal rule followed by a setext heading.
public enum FrontMatter {
    /// The block including both delimiter lines (not the line break after the closing one), in UTF-16 units.
    public static func range(in text: String) -> NSRange? {
        let source = text as NSString
        let first = source.lineRange(for: NSRange(location: 0, length: 0))
        guard source.length > 0, delimiter(in: source, line: first) == "---" else { return nil }
        var location = NSMaxRange(first)
        while location < source.length {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            if let closing = delimiter(in: source, line: line), closing == "---" || closing == "..." {
                return NSRange(location: 0, length: NSMaxRange(content(of: line, in: source)))
            }
            location = NSMaxRange(line)
        }
        return nil
    }

    /// The text with the delimiters turned into `~~~` fences, so the parser sees a code block, and the math scanner
    /// (which skips code) leaves `$` in the YAML alone. Lengths and lines are unchanged, so positions still match.
    static func fenced(_ text: String) -> String {
        guard let range = range(in: text) else { return text }
        let source = NSMutableString(string: text)
        let closing = source.lineRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0)).location
        source.replaceCharacters(in: NSRange(location: closing, length: 3), with: "~~~")
        source.replaceCharacters(in: NSRange(location: 0, length: 3), with: "~~~")
        return source as String
    }

    /// The text with the front matter replaced by its line breaks, so Read mode hides it and line numbers stay put.
    static func removed(_ text: String) -> String {
        guard let range = range(in: text) else { return text }
        let source = text as NSString
        let lineBreaks = source.substring(with: range).count { $0.isNewline }
        return String(repeating: "\n", count: lineBreaks) + source.substring(from: NSMaxRange(range))
    }

    /// A line's text without its line break and trailing spaces or tabs, if it is a front matter delimiter.
    private static func delimiter(in source: NSString, line: NSRange) -> String? {
        let text = source.substring(with: content(of: line, in: source))
        let trimmed = text.replacing(/[ \t]+$/, with: "")
        return trimmed == "---" || trimmed == "..." ? trimmed : nil
    }

    private static func content(of line: NSRange, in source: NSString) -> NSRange {
        var end = NSMaxRange(line)
        while end > line.location, [10, 13].contains(source.character(at: end - 1)) { end -= 1 }
        return NSRange(location: line.location, length: end - line.location)
    }
}
