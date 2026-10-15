import Foundation

/// Read-only helpers over the document for Vim motions. Positions are UTF-16 offsets, and every step
/// moves by whole characters (composed sequences), so emoji and accents are never split.
struct VimText {
    let text: NSString

    init(_ text: NSString) { self.text = text }

    var length: Int { text.length }

    func substring(_ range: Range<Int>) -> String { text.substring(with: NSRange(range)) }

    // MARK: Characters

    func isNewline(_ position: Int) -> Bool {
        guard position >= 0, position < length else { return false }
        let unit = text.character(at: position)
        return unit == 0x0A || unit == 0x0D
    }

    func isBlank(_ position: Int) -> Bool {
        guard position >= 0, position < length else { return false }
        let unit = text.character(at: position)
        return unit == 0x20 || unit == 0x09
    }

    func character(at position: Int) -> String {
        guard position < length else { return "" }
        return text.substring(with: text.rangeOfComposedCharacterSequence(at: position))
    }

    func next(_ position: Int) -> Int {
        position >= length ? length : NSMaxRange(text.rangeOfComposedCharacterSequence(at: position))
    }

    func previous(_ position: Int) -> Int {
        position <= 0 ? 0 : text.rangeOfComposedCharacterSequence(at: min(position, length) - 1).location
    }

    /// 0 = whitespace or line break, 1 = word characters, 2 = punctuation. `big` merges 1 and 2 (WORDs).
    func characterClass(at position: Int, big: Bool) -> Int {
        guard position < length else { return 0 }
        let unit = text.character(at: position)
        if unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D { return 0 }
        if big { return 1 }
        if UTF16.isLeadSurrogate(unit) || UTF16.isTrailSurrogate(unit) || unit == 0x5F { return 1 }
        guard let scalar = Unicode.Scalar(unit) else { return 1 }
        return CharacterSet.alphanumerics.contains(scalar) ? 1 : 2
    }

    // MARK: Lines

    private func lineRange(_ position: Int) -> NSRange {
        text.lineRange(for: NSRange(location: min(max(position, 0), length), length: 0))
    }

    func lineStart(_ position: Int) -> Int { lineRange(position).location }

    /// The end of the line including its line break.
    func lineEnd(_ position: Int) -> Int { NSMaxRange(lineRange(position)) }

    /// The end of the line's text, before its line break.
    func contentEnd(_ position: Int) -> Int {
        let start = lineStart(position)
        var end = lineEnd(position)
        while end > start, isNewline(end - 1) { end -= 1 }
        return end
    }

    func isEmptyLine(_ position: Int) -> Bool { contentEnd(position) == lineStart(position) }

    func isBlankLine(_ position: Int) -> Bool {
        substring(lineStart(position)..<contentEnd(position)).allSatisfy(\.isWhitespace)
    }

    func firstNonBlank(_ position: Int) -> Int {
        var current = lineStart(position)
        let end = contentEnd(position)
        while current < end, isBlank(current) { current += 1 }
        return current
    }

    func indentation(_ position: Int) -> String { substring(lineStart(position)..<firstNonBlank(position)) }

    /// 0-based line index.
    func lineIndex(_ position: Int) -> Int {
        var count = 0
        let end = min(position, length)
        var index = 0
        while index < end {
            let unit = text.character(at: index)
            if unit == 0x0A || (unit == 0x0D && (index + 1 >= length || text.character(at: index + 1) != 0x0A)) {
                count += 1
            }
            index += 1
        }
        return count
    }

    /// Like Vim, a final line break ends the last line rather than starting an empty one:
    /// "a\nb\n" has two lines, and the cursor never rests after the final break.
    var endsWithLineBreak: Bool { length > 0 && isNewline(length - 1) }

    var lineCount: Int { lineIndex(length) + (endsWithLineBreak ? 0 : 1) }

    var lastLineStart: Int { lineStart(forLine: lineCount - 1) }

    func lineStart(forLine index: Int) -> Int {
        var position = 0
        for _ in 0..<min(max(index, 0), max(lineCount - 1, 0)) {
            let end = lineEnd(position)
            if end == position { break }
            position = end
        }
        return position
    }

    func isLineStart(_ position: Int) -> Bool { position == 0 || isNewline(position - 1) }

    /// Normal mode keeps the cursor on a character, never on a line break (unless the line is empty).
    func clampNormal(_ position: Int) -> Int {
        var position = min(max(position, 0), length)
        // The spot after a final line break belongs to the last line.
        if position == length, endsWithLineBreak { position = length - 1 }
        let start = lineStart(position)
        let end = contentEnd(position)
        if end == start { return start }
        return position >= end ? previous(end) : position
    }
}
