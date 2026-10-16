import Foundation

/// Which lines focus mode keeps at full strength.
public enum FocusParagraph {
    /// The lines the selection touches, including their line breaks, in UTF-16 units.
    ///
    /// When those lines are all blank (the caret after pressing Return twice, or between paragraphs), the
    /// nearest non-blank line above stays in focus, as it is the one just written; at the start of a document
    /// it is the nearest one below. Returns nil when the text has no non-blank line.
    public static func range(in string: NSString, selection: NSRange) -> NSRange? {
        let length = string.length
        guard length > 0 else { return nil }
        let start = min(max(selection.location, 0), length)
        let end = min(max(start + max(selection.length, 0), start), length)
        let lines = string.lineRange(for: NSRange(location: start, length: end - start))
        if !isBlank(string, lines) { return lines }

        var location = lines.location
        while location > 0 {
            let line = string.lineRange(for: NSRange(location: location - 1, length: 0))
            if !isBlank(string, line) { return line }
            location = line.location
        }
        location = NSMaxRange(lines)
        while location < length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            if !isBlank(string, line) { return line }
            location = NSMaxRange(line)
        }
        return nil
    }

    private static func isBlank(_ text: NSString, _ range: NSRange) -> Bool {
        text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, options: [], range: range)
            .location == NSNotFound
    }
}
