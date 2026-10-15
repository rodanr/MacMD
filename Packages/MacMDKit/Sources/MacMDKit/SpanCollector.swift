import Foundation
import Markdown

/// Walks the Markdown AST and produces editor style spans in UTF-16 coordinates.
public enum SpanCollector {
    public static func collect(_ text: String) -> StyleResult {
        let math = MathExtractor.spans(in: text)
        let document = MarkdownParser.parse(MathExtractor.masked(text, spans: math))
        var walker = SpanWalker(text: text as NSString, mapper: SourceRangeMapper(text))
        walker.visit(document)
        var spans = walker.spans
        spans += math.map { StyleSpan(range: $0.range, kind: .math) }
        return StyleResult(spans: spans, blocks: blocks(of: document, spans: spans, walker: walker))
    }

    public static func spans(for text: String) -> [StyleSpan] {
        collect(text).spans.sorted { $0.range.location < $1.range.location }
    }

    private static func blocks(of document: Document, spans: [StyleSpan], walker: SpanWalker) -> [StyledBlock] {
        let ranges = document.children.compactMap { walker.mapper.nsRange($0.range) }
        guard !ranges.isEmpty else { return [] }
        var buckets = Array(repeating: [StyleSpan](), count: ranges.count)
        for span in spans {
            // Spans are attached to the last block that starts at or before them.
            var low = 0
            var high = ranges.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if ranges[mid].location <= span.range.location { low = mid } else { high = mid - 1 }
            }
            buckets[low].append(span)
        }
        return zip(ranges, buckets).map { range, blockSpans in
            var hasher = Hasher()
            hasher.combine(walker.text.substring(with: range))
            for span in blockSpans.sorted(by: {
                ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length)
            }) {
                hasher.combine(span.range.location - range.location)
                hasher.combine(span.range.length)
                hasher.combine(span.kind)
            }
            return StyledBlock(range: range, spans: blockSpans, signature: hasher.finalize())
        }
    }
}

private struct SpanWalker: MarkupWalker {
    let text: NSString
    let mapper: SourceRangeMapper
    var spans: [StyleSpan] = []

    init(text: NSString, mapper: SourceRangeMapper) {
        self.text = text
        self.mapper = mapper
    }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) {
        guard let range = mapper.nsRange(heading.range) else { return }
        add(range, .heading(level: heading.level))
        markOuterDelimiters(of: heading, in: range)
        descendInto(heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let range = mapper.nsRange(codeBlock.range) else { return }
        add(range, .codeBlock(language: codeBlock.language))
        let content = text.substring(with: range)
        let trimmed = content.drop { $0 == " " }
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return }
        let firstLine = text.lineRange(for: NSRange(location: range.location, length: 0))
        let opening = NSIntersectionRange(range, firstLine).trimmingTrailingNewline(in: text)
        add(opening, .syntaxMarker)
        let lastLine = text.lineRange(for: NSRange(location: max(NSMaxRange(range) - 1, range.location), length: 0))
        let closing = NSIntersectionRange(range, lastLine).trimmingTrailingNewline(in: text)
        let closingText = text.substring(with: closing).trimmingCharacters(in: .whitespaces)
        if closing.location > opening.location, let fence = trimmed.first,
            !closingText.isEmpty, closingText.allSatisfy({ $0 == fence })
        {
            add(closing, .syntaxMarker)
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = mapper.nsRange(blockQuote.range) else { return }
        add(range, .blockQuote)
        let text = self.text
        var markers: [StyleSpan] = []
        text.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            var position = lineRange.location
            while position < NSMaxRange(lineRange), text.character(at: position) == 0x20 { position += 1 }
            guard position < NSMaxRange(lineRange), text.character(at: position) == 0x3E else { return }
            var end = position + 1
            if end < NSMaxRange(lineRange), text.character(at: end) == 0x20 { end += 1 }
            markers.append(StyleSpan(range: NSRange(location: position, length: end - position), kind: .syntaxMarker))
        }
        spans += markers
        descendInto(blockQuote)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        guard let range = mapper.nsRange(listItem.range) else { return }
        let contentStart = listItem.child(at: 0).flatMap { mapper.nsRange($0.range)?.location } ?? NSMaxRange(range)
        let prefix = text.substring(with: NSRange(location: range.location, length: contentStart - range.location))
        if let match = prefix.firstMatch(of: /^([-+*]|\d{1,9}[.)])[ \t]*/) {
            let markerLength = (String(match.output.0) as NSString).length
            add(NSRange(location: range.location, length: markerLength), .listMarker)
            if let checkbox = listItem.checkbox {
                let boxStart = range.location + markerLength
                if boxStart + 3 <= contentStart {
                    add(NSRange(location: boxStart, length: 3), .taskBox(checked: checkbox == .checked))
                }
            }
        }
        descendInto(listItem)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let range = mapper.nsRange(thematicBreak.range) else { return }
        add(range.trimmingTrailingNewline(in: text), .thematicBreak)
    }

    mutating func visitTable(_ table: Table) {
        guard let range = mapper.nsRange(table.range) else { return }
        add(range, .table)
        descendInto(table)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        guard let range = mapper.nsRange(html.range) else { return }
        add(range.trimmingTrailingNewline(in: text), .html)
    }

    // MARK: Inlines

    mutating func visitStrong(_ strong: Strong) { inlineContainer(strong, .strong) }
    mutating func visitEmphasis(_ emphasis: Emphasis) { inlineContainer(emphasis, .emphasis) }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) { inlineContainer(strikethrough, .strikethrough) }
    mutating func visitLink(_ link: Link) { inlineContainer(link, .link) }
    mutating func visitImage(_ image: Image) { inlineContainer(image, .image) }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = mapper.nsRange(inlineCode.range) else { return }
        add(range, .inlineCode)
        var ticks = 0
        while ticks < range.length, text.character(at: range.location + ticks) == 0x60 { ticks += 1 }
        guard ticks > 0, range.length >= ticks * 2 else { return }
        add(NSRange(location: range.location, length: ticks), .syntaxMarker)
        add(NSRange(location: NSMaxRange(range) - ticks, length: ticks), .syntaxMarker)
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        guard let range = mapper.nsRange(inlineHTML.range) else { return }
        add(range, .html)
    }

    // MARK: Helpers

    private mutating func inlineContainer(_ markup: Markup, _ kind: StyleKind) {
        guard let range = mapper.nsRange(markup.range) else { return }
        add(range, kind)
        markOuterDelimiters(of: markup, in: range)
        descendInto(markup)
    }

    /// Marks the source between a container's edges and its children as syntax.
    private mutating func markOuterDelimiters(of markup: Markup, in range: NSRange) {
        let childRanges = markup.children.compactMap { mapper.nsRange($0.range) }
        guard let first = childRanges.first, let last = childRanges.last else {
            add(range.trimmingTrailingNewline(in: text), .syntaxMarker)
            return
        }
        add(NSRange(location: range.location, length: first.location - range.location), .syntaxMarker)
        add(NSRange(location: NSMaxRange(last), length: NSMaxRange(range) - NSMaxRange(last)), .syntaxMarker)
    }

    private mutating func add(_ range: NSRange, _ kind: StyleKind) {
        guard range.length > 0, range.location >= 0, NSMaxRange(range) <= text.length else { return }
        spans.append(StyleSpan(range: range, kind: kind))
    }
}

extension NSRange {
    func trimmingTrailingNewline(in text: NSString) -> NSRange {
        var result = self
        while result.length > 0 {
            let unit = text.character(at: NSMaxRange(result) - 1)
            guard unit == 0x0A || unit == 0x0D else { break }
            result.length -= 1
        }
        return result
    }
}
