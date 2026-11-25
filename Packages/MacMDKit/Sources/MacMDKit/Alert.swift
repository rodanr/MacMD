import Foundation
import Markdown

/// The five GitHub alert types: a top-level quote whose first line is only `[!NOTE]`, `[!TIP]` and so on.
public enum AlertKind: String, CaseIterable, Hashable, Sendable {
    case note, tip, important, warning, caution

    /// The heading Read mode shows above the alert.
    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Recognizes GitHub alerts in the parsed document, shared by the editor and Read mode so both agree.
enum Alert {
    /// The alert type of `quote`, or `nil` for an ordinary quote. Like GitHub, only quotes at the top level of
    /// the document count, and the marker must be alone on the quote's first line (case doesn't matter).
    static func kind(of quote: BlockQuote) -> AlertKind? {
        guard quote.parent is Document, let paragraph = quote.child(at: 0) as? Paragraph else { return nil }
        let firstLine = Array(paragraph.inlineChildren).prefix { !($0 is SoftBreak || $0 is LineBreak) }
        let marker = firstLine.map { ($0 as? PlainTextConvertibleMarkup)?.plainText ?? "" }.joined()
        guard let match = marker.trimmingCharacters(in: .whitespaces).wholeMatch(of: /\[!([A-Za-z]+)\]/) else {
            return nil
        }
        return AlertKind(rawValue: match.output.1.lowercased())
    }

    /// The inline content of `paragraph` after its first line: what's left of the first paragraph once the marker
    /// line is taken out.
    static func inlinesAfterMarker(in paragraph: Paragraph) -> [InlineMarkup] {
        let inlines = Array(paragraph.inlineChildren)
        guard let breakIndex = inlines.firstIndex(where: { $0 is SoftBreak || $0 is LineBreak }) else { return [] }
        return Array(inlines[(breakIndex + 1)...])
    }
}
