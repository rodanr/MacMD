import Foundation

/// The semantic role of a range of Markdown source, used by the editor to pick attributes.
public enum StyleKind: Hashable, Sendable {
    case heading(level: Int)
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case codeBlock(language: String?)
    case link
    case image
    case blockQuote
    case listMarker
    case taskBox(checked: Bool)
    case thematicBreak
    case table
    case html
    case math
    /// Markdown punctuation (`#`, `**`, backticks, `>` …) that the editor renders faintly.
    case syntaxMarker
}

/// A styled range of the source text, in UTF-16 units.
public struct StyleSpan: Hashable, Sendable {
    public let range: NSRange
    public let kind: StyleKind

    public init(range: NSRange, kind: StyleKind) {
        self.range = range
        self.kind = kind
    }
}

/// A top-level block of the document with the spans that fall inside it.
///
/// `signature` identifies the block's text and styling independently of its position,
/// so the editor can skip restyling blocks that did not change.
public struct StyledBlock: Hashable, Sendable {
    public let range: NSRange
    public let spans: [StyleSpan]
    public let signature: Int
}

/// The result of styling a whole document.
public struct StyleResult: Sendable {
    public let spans: [StyleSpan]
    public let blocks: [StyledBlock]
}
