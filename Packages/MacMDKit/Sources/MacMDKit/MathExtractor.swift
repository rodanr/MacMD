import Foundation

/// A TeX math span found in Markdown source: `$inline$` or `$$display$$`.
public struct MathSpan: Hashable, Sendable {
    /// Range of the span including its `$` delimiters, in UTF-16 units of the source.
    public let range: NSRange
    public let tex: String
    public let isDisplay: Bool
}

/// Finds TeX math outside of code and protects it from the Markdown parser,
/// which would otherwise consume backslashes and treat `_` as emphasis.
public enum MathExtractor {
    static let tokenStart: Character = "\u{E000}"
    static let tokenEnd: Character = "\u{E001}"
    /// Fills the lines a multi-line math span used to occupy, so line numbers stay stable.
    static let lineFiller: Character = "\u{E002}"

    public static func spans(in text: String) -> [MathSpan] {
        let units = Array(text.utf16)
        var scanner = Scanner(units: units)
        return scanner.scan().map { range in
            let delimiter = isDisplay(range, units) ? 2 : 1
            let inner = NSRange(location: range.location + delimiter, length: range.length - 2 * delimiter)
            return MathSpan(
                range: range,
                tex: (text as NSString).substring(with: inner),
                isDisplay: delimiter == 2
            )
        }
    }

    /// Replaces math with filler of identical UTF-8 length (newlines kept), so parser
    /// source locations still line up with the original text.
    public static func masked(_ text: String, spans: [MathSpan]) -> String {
        guard !spans.isEmpty else { return text }
        let source = text as NSString
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var cursor = 0
        for span in spans {
            result += source.substring(with: NSRange(location: cursor, length: span.range.location - cursor))
            for scalar in source.substring(with: span.range).unicodeScalars {
                if scalar == "\n" || scalar == "\r" {
                    result.unicodeScalars.append(scalar)
                } else {
                    result += String(repeating: "x", count: String(scalar).utf8.count)
                }
            }
            cursor = NSMaxRange(span.range)
        }
        result += source.substring(from: cursor)
        return result
    }

    /// Replaces each math span with a private-use token (`\u{E000}<index>\u{E001}`),
    /// padding with line-filler lines so the line count is unchanged.
    public static func replacingWithPlaceholders(_ text: String) -> (text: String, table: [Int: MathSpan]) {
        let spans = spans(in: text)
        guard !spans.isEmpty else { return (text, [:]) }
        let source = text as NSString
        var result = ""
        var table: [Int: MathSpan] = [:]
        var cursor = 0
        for (index, span) in spans.enumerated() {
            table[index] = span
            result += source.substring(with: NSRange(location: cursor, length: span.range.location - cursor))
            let newlines = source.substring(with: span.range).reduce(0) { $1.isNewline ? $0 + 1 : $0 }
            result += "\(tokenStart)\(index)"
            result += String(repeating: "\n\(lineFiller)", count: newlines)
            result.append(tokenEnd)
            cursor = NSMaxRange(span.range)
        }
        result += source.substring(from: cursor)
        return (result, table)
    }

    private static func isDisplay(_ range: NSRange, _ units: [UInt16]) -> Bool {
        range.length >= 4 && units[range.location + 1] == dollar
    }
}

private let dollar = UInt16(UInt8(ascii: "$"))
private let backtick = UInt16(UInt8(ascii: "`"))
private let tilde = UInt16(UInt8(ascii: "~"))
private let backslash = UInt16(UInt8(ascii: "\\"))
private let newline = UInt16(UInt8(ascii: "\n"))
private let space = UInt16(UInt8(ascii: " "))

private struct Scanner {
    let units: [UInt16]
    var index = 0

    init(units: [UInt16]) { self.units = units }

    mutating func scan() -> [NSRange] {
        var found: [NSRange] = []
        var atLineStart = true
        while index < units.count {
            if atLineStart, skipFencedCodeBlock() { continue }
            let unit = units[index]
            atLineStart = unit == newline
            switch unit {
            case backslash:
                index += 2
            case backtick:
                skipCodeSpan()
            case dollar:
                if let range = displayMath() ?? inlineMath() {
                    found.append(range)
                    index = NSMaxRange(range)
                } else {
                    index += 1
                }
            default:
                index += 1
            }
        }
        return found
    }

    /// If a fence opens at `index` (a line start), skips past its closing fence.
    private mutating func skipFencedCodeBlock() -> Bool {
        guard let (fenceChar, fenceLength) = fence(at: index) else { return false }
        var lineStart = endOfLine(from: index) + 1
        while lineStart < units.count {
            if let (char, length) = fence(at: lineStart), char == fenceChar, length >= fenceLength {
                index = endOfLine(from: lineStart) + 1
                return true
            }
            lineStart = endOfLine(from: lineStart) + 1
        }
        index = units.count
        return true
    }

    private func fence(at start: Int) -> (UInt16, Int)? {
        var position = start
        while position < units.count, units[position] == space, position - start < 3 { position += 1 }
        guard position < units.count, units[position] == backtick || units[position] == tilde else { return nil }
        let char = units[position]
        var length = 0
        while position < units.count, units[position] == char {
            length += 1
            position += 1
        }
        return length >= 3 ? (char, length) : nil
    }

    private func endOfLine(from start: Int) -> Int {
        var position = start
        while position < units.count, units[position] != newline { position += 1 }
        return position
    }

    private mutating func skipCodeSpan() {
        let runLength = run(of: backtick, at: index)
        var position = index + runLength
        while position < units.count {
            if units[position] == backtick {
                let closing = run(of: backtick, at: position)
                if closing == runLength {
                    index = position + closing
                    return
                }
                position += closing
            } else {
                position += 1
            }
        }
        index += runLength
    }

    private func run(of unit: UInt16, at start: Int) -> Int {
        var position = start
        while position < units.count, units[position] == unit { position += 1 }
        return position - start
    }

    private func displayMath() -> NSRange? {
        guard index + 1 < units.count, units[index + 1] == dollar else { return nil }
        var position = index + 2
        while position + 1 < units.count {
            if units[position] == backslash {
                position += 2
                continue
            }
            if units[position] == dollar, units[position + 1] == dollar {
                return position > index + 2 ? NSRange(location: index, length: position + 2 - index) : nil
            }
            position += 1
        }
        return nil
    }

    private func inlineMath() -> NSRange? {
        let start = index + 1
        guard start < units.count, !isWhitespace(units[start]), units[start] != dollar else { return nil }
        var position = start
        while position < units.count {
            let unit = units[position]
            if unit == backslash {
                position += 2
                continue
            }
            if unit == newline, position + 1 < units.count, units[position + 1] == newline { return nil }
            if unit == dollar {
                let followedByDigit = position + 1 < units.count && isDigit(units[position + 1])
                if !isWhitespace(units[position - 1]), !followedByDigit {
                    return NSRange(location: index, length: position + 1 - index)
                }
                return nil
            }
            position += 1
        }
        return nil
    }

    private func isWhitespace(_ unit: UInt16) -> Bool {
        unit == space || unit == newline || unit == 9 || unit == 13
    }

    private func isDigit(_ unit: UInt16) -> Bool { unit >= 48 && unit <= 57 }
}
