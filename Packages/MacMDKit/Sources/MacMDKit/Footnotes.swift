import Foundation

/// A footnote definition: `[^label]: text`, continued by the indented lines right after it.
public struct FootnoteDefinition: Hashable, Sendable {
    /// The label in lowercase: labels match regardless of case.
    public let label: String
    /// The whole definition, continuation lines included (not the final line break), in UTF-16 units.
    public let range: NSRange
    /// `[^label]:` at the start of the definition.
    public let labelRange: NSRange
    /// The note's Markdown, continuation lines unindented.
    public let content: String
    /// 1-based line of `[^label]:`.
    public let line: Int
}

/// Footnotes (`text[^1]` … `[^1]: note`). swift-markdown has no footnote support, and would even read a one-word
/// definition such as `[^1]: Yes` as a link definition, so definitions are found before parsing and references
/// are found in the parsed text. Shared by the editor, Read mode and the outline so they agree.
enum Footnotes {
    /// `[^label]` where the label has no spaces, brackets or carets.
    static var reference: Regex<(Substring, Substring)> { /\[\^([^\]\[\s^]+)\]/ }

    /// Definitions outside code, in source order; for a repeated label only the first counts. Run on text whose
    /// front matter was `FrontMatter.fenced`, so definitions inside it are skipped like code.
    static func definitions(in text: String) -> [FootnoteDefinition] {
        let source = text as NSString
        var definitions: [FootnoteDefinition] = []
        var seen: Set<String> = []
        var fence: (character: Character, length: Int)?
        var location = 0
        var line = 1
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            let content = lineText(lineRange, in: source)
            location = NSMaxRange(lineRange)
            let lineNumber = line
            line += 1
            if let open = fence {
                if let close = Self.fence(in: content), close.character == open.character, close.length >= open.length,
                    content.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == open.character })
                {
                    fence = nil
                }
                continue
            }
            if let open = Self.fence(in: content) {
                fence = open
                continue
            }
            // Cheap test first: regex matching on every line of a long document is slow.
            guard content.drop(while: { $0 == " " }).hasPrefix("[^"),
                let match = content.prefixMatch(of: /( {0,3})\[\^([^\]\[\s^]+)\]:[ \t]*/)
            else { continue }
            let indent = match.output.1.utf16.count
            let labelEnd = (content[..<match.range.upperBound].trimmingCharacters(in: .whitespaces) as NSString).length
            var lines = [String(content[match.range.upperBound...])]
            var end = lineRange.location + (content as NSString).length
            // Indented, non-blank lines continue the note.
            while location < source.length {
                let nextRange = source.lineRange(for: NSRange(location: location, length: 0))
                let next = lineText(nextRange, in: source)
                guard next.first == " " || next.first == "\t", !next.trimmingCharacters(in: .whitespaces).isEmpty
                else { break }
                lines.append(next.trimmingCharacters(in: .whitespaces))
                end = nextRange.location + (next as NSString).length
                location = NSMaxRange(nextRange)
                line += 1
            }
            let label = match.output.2.lowercased()
            guard seen.insert(label).inserted else { continue }
            definitions.append(
                FootnoteDefinition(
                    label: label,
                    range: NSRange(location: lineRange.location, length: end - lineRange.location),
                    labelRange: NSRange(location: lineRange.location + indent, length: labelEnd - indent),
                    content: lines.joined(separator: "\n"), line: lineNumber))
        }
        return definitions
    }

    private static func lineText(_ range: NSRange, in source: NSString) -> String {
        source.substring(with: range).trimmingCharacters(in: .newlines)
    }

    /// The text with each definition's `[` swapped for `x`, so the parser can't read it as a link definition and
    /// the note stays an ordinary paragraph for the editor to style. Lengths are unchanged.
    static func neutralized(_ text: String, definitions: [FootnoteDefinition]) -> String {
        guard !definitions.isEmpty else { return text }
        let source = NSMutableString(string: text)
        for definition in definitions {
            source.replaceCharacters(in: NSRange(location: definition.labelRange.location, length: 1), with: "x")
        }
        return source as String
    }

    /// The text with every definition replaced by its line breaks: Read mode lists the notes at the end instead,
    /// and line numbers stay put.
    static func removed(_ text: String, definitions: [FootnoteDefinition]) -> String {
        guard !definitions.isEmpty else { return text }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for definition in definitions.sorted(by: { $0.range.location < $1.range.location }) {
            result += source.substring(with: NSRange(location: cursor, length: definition.range.location - cursor))
            result += String(repeating: "\n", count: source.substring(with: definition.range).count { $0.isNewline })
            cursor = NSMaxRange(definition.range)
        }
        return result + source.substring(from: cursor)
    }

    /// `text` without references to `labels`, for heading titles in the outline and anchors.
    static func strippingReferences(from text: String, labels: Set<String>) -> String {
        guard !labels.isEmpty else { return text }
        return text.replacing(reference) { match in labels.contains(match.output.1.lowercased()) ? "" : match.output.0 }
            .trimmingCharacters(in: .whitespaces)
    }

    private static func fence(in line: String) -> (character: Character, length: Int)? {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3, let first = trimmed.first, first == "`" || first == "~" else {
            return nil
        }
        let length = trimmed.prefix { $0 == first }.count
        return length >= 3 ? (first, length) : nil
    }
}
