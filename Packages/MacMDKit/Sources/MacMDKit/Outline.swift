import Markdown

/// A heading in the document outline.
public struct OutlineItem: Hashable, Sendable, Identifiable {
    public let level: Int
    public let title: String
    /// Anchor id, identical to the one `HTMLRenderer` assigns to the heading.
    public let slug: String
    /// 1-based source line of the heading.
    public let line: Int

    public var id: String { slug }
}

public enum Outline {
    public static func items(for text: String) -> [OutlineItem] {
        let (prepared, math) = MathExtractor.replacingWithPlaceholders(text)
        var slugger = Slugger()
        return MarkdownParser.parse(prepared).children.compactMap { block in
            guard let heading = block as? Heading, let line = heading.range?.lowerBound.line else { return nil }
            let title = HeadingTitle.plainText(of: heading, math: math)
            return OutlineItem(level: heading.level, title: title, slug: slugger.slug(title), line: line)
        }
    }
}

/// Plain-text heading titles, shared by the outline and HTML anchors so they always agree.
enum HeadingTitle {
    static func plainText(of heading: Heading, math: [Int: MathSpan]) -> String {
        Placeholder.restoringTeX(in: heading.plainText, math: math)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
