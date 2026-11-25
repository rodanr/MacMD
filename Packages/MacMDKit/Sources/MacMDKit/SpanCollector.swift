import Foundation
import Markdown

/// Walks the Markdown AST and produces editor style spans in UTF-16 coordinates.
public enum SpanCollector {
    public static func collect(_ text: String) -> StyleResult {
        // Front matter is parsed as a fenced code block; positions are unchanged, so spans map onto `text`.
        // Footnote definitions are found first and defused, so the parser can't take one for a link definition.
        let fenced = FrontMatter.fenced(text)
        let footnotes = Footnotes.definitions(in: fenced)
        let source = Footnotes.neutralized(fenced, definitions: footnotes)
        let math = MathExtractor.spans(in: source)
        let document = MarkdownParser.parse(MathExtractor.masked(source, spans: math))
        var walker = SpanWalker(text: text as NSString, mapper: SourceRangeMapper(text), footnotes: footnotes)
        walker.visit(document)
        var spans = walker.spans
        spans += math.map { StyleSpan(range: $0.range, kind: .math) }
        spans += frontMatterDelimiters(in: text)
        for footnote in footnotes {
            spans.append(StyleSpan(range: footnote.range, kind: .footnoteDefinition))
            spans.append(StyleSpan(range: footnote.labelRange, kind: .syntaxMarker))
        }
        return StyleResult(spans: spans, blocks: blocks(of: document, spans: spans, walker: walker))
    }

    /// The `---` lines around front matter, dimmed like code fences.
    private static func frontMatterDelimiters(in text: String) -> [StyleSpan] {
        guard let range = FrontMatter.range(in: text) else { return [] }
        let closing = (text as NSString).lineRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0)).location
        return [
            StyleSpan(range: NSRange(location: 0, length: 3), kind: .syntaxMarker),
            StyleSpan(range: NSRange(location: closing, length: 3), kind: .syntaxMarker),
        ]
    }

    public static func spans(for text: String) -> [StyleSpan] {
        collect(text).spans.sorted { $0.range.location < $1.range.location }
    }

    private static func blocks(of document: Document, spans: [StyleSpan], walker: SpanWalker) -> [StyledBlock] {
        var ranges = document.children.compactMap { walker.mapper.nsRange($0.range) }
        guard !ranges.isEmpty else { return [] }
        // Blocks never overlap, even where the parser's ranges do (see `endingAtUnderline`).
        for index in ranges.indices.dropLast() where NSMaxRange(ranges[index]) > ranges[index + 1].location {
            ranges[index].length = max(ranges[index + 1].location - ranges[index].location, 0)
        }
        var buckets = Array(repeating: [StyleSpan](), count: ranges.count)
        for span in spans where span.range.length > 0 {
            // A span belongs to every block it overlaps (display math can run across several), so a block's
            // signature changes whenever any styling on its text changes, and the editor restyles it.
            var low = 0
            var high = ranges.count
            while low < high {
                let mid = (low + high) / 2
                if NSMaxRange(ranges[mid]) <= span.range.location { low = mid + 1 } else { high = mid }
            }
            var index = low
            while index < ranges.count, ranges[index].location < NSMaxRange(span.range) {
                if NSIntersectionRange(ranges[index], span.range).length > 0 { buckets[index].append(span) }
                index += 1
            }
        }
        return zip(ranges, buckets).map { range, blockSpans in
            var hasher = Hasher()
            // A line's layout comes from its first character. Include any text on the block's first line before
            // the block (indentation, a quote marker), so adding or removing it counts as a change.
            let lineStart = walker.text.lineRange(for: NSRange(location: range.location, length: 0)).location
            hasher.combine(
                walker.text.substring(with: NSRange(location: lineStart, length: range.location - lineStart)))
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
    /// Labels with a definition, and the definitions' own `[^label]:` (which aren't references).
    private let footnoteLabels: Set<String>
    private let footnoteLabelRanges: [NSRange]
    /// Inside a link or image, where a footnote reference would nest one link in another.
    private var linkDepth = 0

    init(text: NSString, mapper: SourceRangeMapper, footnotes: [FootnoteDefinition] = []) {
        self.text = text
        self.mapper = mapper
        self.footnoteLabels = Set(footnotes.map(\.label))
        self.footnoteLabelRanges = footnotes.map(\.labelRange)
    }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) {
        guard let range = mapper.nsRange(heading.range).map({ endingAtUnderline($0, heading) }) else { return }
        add(range, .heading(level: heading.level))
        markOuterDelimiters(of: heading, in: range)
        descendInto(heading)
    }

    /// cmark reports a setext heading (`Title` over `---`) as running into the next line when a paragraph
    /// follows directly; end it at its underline instead.
    func endingAtUnderline(_ range: NSRange, _ heading: Heading) -> NSRange {
        let start = range.location
        var first = start
        while first < NSMaxRange(range), text.character(at: first) == 0x20 { first += 1 }
        guard first < NSMaxRange(range), text.character(at: first) != 0x23,  // not an ATX "#" heading
            let lastChild = heading.children.compactMap({ mapper.nsRange($0.range) }).last
        else { return range }
        let contentLine = text.lineRange(for: NSRange(location: max(NSMaxRange(lastChild) - 1, start), length: 0))
        guard NSMaxRange(contentLine) < NSMaxRange(range) else { return range }
        let underline = text.lineRange(for: NSRange(location: NSMaxRange(contentLine), length: 0))
        return NSRange(start..<min(NSMaxRange(underline), NSMaxRange(range))).trimmingTrailingNewline(in: text)
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
        if let kind = Alert.kind(of: blockQuote), let paragraph = blockQuote.child(at: 0),
            let start = mapper.nsRange(paragraph.range)?.location
        {
            add(range, .alert(kind))
            let line = text.lineRange(for: NSRange(location: start, length: 0))
            let marker = text.substring(with: NSRange(location: start, length: NSMaxRange(line) - start))
            let length = (marker.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).length
            add(NSRange(location: start, length: length), .alertTitle(kind))
        }
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
    mutating func visitLink(_ link: Link) {
        linkDepth += 1
        inlineContainer(link, .link)
        linkDepth -= 1
    }

    mutating func visitImage(_ image: Image) {
        linkDepth += 1
        inlineContainer(image, .image)
        linkDepth -= 1
    }

    /// Footnote references are plain text to the parser; find them in the source this text came from.
    mutating func visitText(_ textNode: Text) {
        guard !footnoteLabels.isEmpty, linkDepth == 0, let range = mapper.nsRange(textNode.range) else { return }
        let source = text.substring(with: range)
        for match in source.matches(of: Footnotes.reference)
        where footnoteLabels.contains(match.output.1.lowercased()) {
            let start = range.location + source.utf16.distance(from: source.startIndex, to: match.range.lowerBound)
            let length = String(match.output.0).utf16.count
            let reference = NSRange(location: start, length: length)
            guard !footnoteLabelRanges.contains(where: { NSIntersectionRange($0, reference).length > 0 }) else {
                continue
            }
            add(reference, .footnoteReference)
            add(NSRange(location: start, length: 2), .syntaxMarker)
            add(NSRange(location: NSMaxRange(reference) - 1, length: 1), .syntaxMarker)
        }
    }

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
