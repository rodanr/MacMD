import Foundation
import Markdown

/// Converts swift-markdown source locations (1-based line, 1-based UTF-8 byte column)
/// into UTF-16 offsets usable with `NSString` / `NSTextStorage`.
public struct SourceRangeMapper: Sendable {
    private let text: String
    /// Start index of every line, in order.
    private let lineStarts: [String.Index]
    /// Index where every line's content ends (before its line terminator).
    private let lineEnds: [String.Index]
    /// UTF-16 offset of every line start.
    private let lineStartOffsets: [Int]

    public init(_ text: String) {
        self.text = text
        var starts: [String.Index] = [text.startIndex]
        var ends: [String.Index] = []
        var offsets: [Int] = [0]
        let utf8 = text.utf8
        var index = utf8.startIndex
        var utf16Offset = 0
        while index != utf8.endIndex {
            let byte = utf8[index]
            if byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                ends.append(index)
                var next = utf8.index(after: index)
                var terminatorLength = 1
                if byte == UInt8(ascii: "\r"), next != utf8.endIndex, utf8[next] == UInt8(ascii: "\n") {
                    next = utf8.index(after: next)
                    terminatorLength = 2
                }
                utf16Offset += text.utf16.distance(from: starts[starts.count - 1], to: index) + terminatorLength
                starts.append(next)
                offsets.append(utf16Offset)
                index = next
            } else {
                index = utf8.index(after: index)
            }
        }
        ends.append(text.endIndex)
        self.lineStarts = starts
        self.lineEnds = ends
        self.lineStartOffsets = offsets
    }

    /// Number of lines in the text (a trailing newline starts a new, empty line).
    public var lineCount: Int { lineStarts.count }

    /// UTF-16 offset of a 1-based line and 1-based UTF-8 column. Columns past the end
    /// of a line are clamped to the line end; invalid lines return `nil`.
    public func utf16Offset(line: Int, column: Int) -> Int? {
        guard line >= 1, line <= lineStarts.count else { return nil }
        let start = lineStarts[line - 1]
        let end = lineEnds[line - 1]
        let utf8 = text.utf8
        let target =
            utf8.index(start, offsetBy: max(column - 1, 0), limitedBy: end) ?? end
        // Round down to a scalar boundary so a malformed column never splits a character.
        let aligned =
            target.samePosition(in: text.unicodeScalars) == nil
            ? text.unicodeScalars.index(before: text.unicodeScalars.index(after: target))
            : target
        return lineStartOffsets[line - 1] + text.utf16.distance(from: start, to: min(aligned, end))
    }

    /// UTF-16 offset of the start of a 1-based line.
    public func utf16Offset(ofLine line: Int) -> Int? {
        guard line >= 1, line <= lineStartOffsets.count else { return nil }
        return lineStartOffsets[line - 1]
    }

    /// 1-based line containing the given UTF-16 offset.
    public func line(containingUTF16Offset offset: Int) -> Int {
        var low = 0
        var high = lineStartOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    /// Converts a swift-markdown `SourceRange` into an `NSRange`.
    public func nsRange(_ range: SourceRange?) -> NSRange? {
        guard let range,
            let lower = utf16Offset(line: range.lowerBound.line, column: range.lowerBound.column),
            let upper = utf16Offset(line: range.upperBound.line, column: range.upperBound.column),
            upper >= lower
        else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }
}
