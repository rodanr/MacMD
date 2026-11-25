import Foundation
import Markdown

/// HTML produced from a Markdown document, plus the optional reader features it needs.
public struct RenderedHTML: Hashable, Sendable {
    public struct Features: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Fenced code with a language → syntax highlighting.
        public static let code = Features(rawValue: 1 << 0)
        /// TeX math → KaTeX.
        public static let math = Features(rawValue: 1 << 1)
        /// ```mermaid blocks → Mermaid.
        public static let mermaid = Features(rawValue: 1 << 2)
    }

    /// The `<body>` content.
    public let body: String
    public let features: Features
}

/// Renders Markdown to semantic HTML for Read mode and export.
///
/// Block elements carry `data-line` (1-based source line) so the reader can keep its
/// scroll position in sync with the editor. Headings get the same anchors as `Outline`.
public enum HTMLRenderer {
    public static func render(_ markdown: String) -> RenderedHTML {
        // Front matter is metadata, not content: Read mode and exports leave it out. Footnote definitions move to
        // a list at the end. Both leave their line breaks behind, so line numbers stay put.
        let withoutFrontMatter = FrontMatter.removed(markdown)
        let definitions = Footnotes.definitions(in: withoutFrontMatter)
        let footnotes = FootnoteNumbering(labels: Set(definitions.map(\.label)))
        let (prepared, math) = MathExtractor.replacingWithPlaceholders(
            Footnotes.removed(withoutFrontMatter, definitions: definitions))
        var visitor = HTMLVisitor(math: math, footnotes: footnotes)
        visitor.visit(MarkdownParser.parse(prepared))
        if !math.isEmpty { visitor.features.insert(.math) }
        var body = visitor.output.trimmingCharacters(in: .newlines)
        var features = visitor.features
        if !definitions.isEmpty {
            body += "\n" + notes(definitions, numbering: footnotes, features: &features)
        }
        return RenderedHTML(body: body, features: features)
    }

    /// The notes list: referenced notes in the order they're first referenced, then the rest in source order.
    /// Notes can refer to other notes, which can add to the order while the list is written.
    private static func notes(
        _ definitions: [FootnoteDefinition], numbering: FootnoteNumbering, features: inout RenderedHTML.Features
    ) -> String {
        let byLabel = Dictionary(definitions.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
        var items = ""
        var written = 0
        func writePending() {
            while written < numbering.order.count {
                let label = numbering.order[written]
                written += 1
                guard let definition = byLabel[label] else { continue }
                items += note(definition, number: written, numbering: numbering, features: &features) + "\n"
            }
        }
        writePending()
        for definition in definitions where numbering.number(of: definition.label) == nil {
            numbering.assignNumber(to: definition.label)
            writePending()
        }
        return "<section class=\"footnotes\">\n<ol>\n\(items)</ol>\n</section>"
    }

    private static func note(
        _ definition: FootnoteDefinition, number: Int, numbering: FootnoteNumbering,
        features: inout RenderedHTML.Features
    ) -> String {
        let (prepared, math) = MathExtractor.replacingWithPlaceholders(definition.content)
        var visitor = HTMLVisitor(math: math, footnotes: numbering, includesLines: false)
        visitor.visit(MarkdownParser.parse(prepared))
        features.formUnion(visitor.features)
        if !math.isEmpty { features.insert(.math) }
        var content = visitor.output.trimmingCharacters(in: .newlines)
        if numbering.referenceCount(of: definition.label) > 0 {
            let back =
                ##"<a href="#fnref:\##(number)" class="footnote-back" aria-label="Back to reference \##(number)">↩</a>"##
            if content.hasSuffix("</p>") {
                content.removeLast(4)
                content += " \(back)</p>"
            } else {
                content += "<p>\(back)</p>"
            }
        }
        return #"<li id="fn:\#(number)">\#(content)</li>"#
    }
}

/// Footnote numbers, in order of first reference, shared by the document and its notes.
private final class FootnoteNumbering {
    let labels: Set<String>
    private(set) var order: [String] = []
    private var numbers: [String: Int] = [:]
    private var references: [String: Int] = [:]

    init(labels: Set<String>) { self.labels = labels }

    func number(of label: String) -> Int? { numbers[label] }
    func referenceCount(of label: String) -> Int { references[label] ?? 0 }

    @discardableResult func assignNumber(to label: String) -> Int {
        if let number = numbers[label] { return number }
        order.append(label)
        numbers[label] = order.count
        return order.count
    }

    /// The number and element id for a new reference to `label`: `fnref:1`, then `fnref:1-2` and so on.
    func reference(to label: String) -> (number: Int, id: String) {
        let number = assignNumber(to: label)
        let count = referenceCount(of: label) + 1
        references[label] = count
        return (number, count == 1 ? "fnref:\(number)" : "fnref:\(number)-\(count)")
    }
}

private struct HTMLVisitor: MarkupWalker {
    let math: [Int: MathSpan]
    let footnotes: FootnoteNumbering
    /// Notes are rendered apart from the document; their elements get no `data-line`, which must only grow down
    /// the page for scroll sync.
    let includesLines: Bool
    var output = ""
    var features: RenderedHTML.Features = []
    private var slugger = Slugger()
    private var tightListDepth: [Bool] = []
    private var tableAlignments: [Table.ColumnAlignment?] = []
    private var inTableHead = false
    /// Inside a link, where a footnote reference would nest one link in another.
    private var linkDepth = 0

    init(math: [Int: MathSpan], footnotes: FootnoteNumbering, includesLines: Bool = true) {
        self.math = math
        self.footnotes = footnotes
        self.includesLines = includesLines
    }

    // MARK: Blocks

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if let span = Placeholder.soleMath(in: paragraph.plainText, math: math) {
            output +=
                #"<div class="math display"\#(lineAttribute(paragraph)) data-tex="\#(escapeAttribute(span.tex))"></div>"#
                + "\n"
            return
        }
        if tightListDepth.last == true {
            descendInto(paragraph)
            return
        }
        output += "<p\(lineAttribute(paragraph))>"
        descendInto(paragraph)
        output += "</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) {
        let slug = slugger.slug(HeadingTitle.plainText(of: heading, math: math, footnotes: footnotes.labels))
        output += #"<h\#(heading.level) id="\#(escapeAttribute(slug))"\#(lineAttribute(heading))>"#
        descendInto(heading)
        output += "</h\(heading.level)>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let kind = Alert.kind(of: blockQuote) else {
            output += "<blockquote\(lineAttribute(blockQuote))>\n"
            tightListDepth.append(false)
            descendInto(blockQuote)
            tightListDepth.removeLast()
            output += "</blockquote>\n"
            return
        }
        output += #"<blockquote class="alert alert-\#(kind.rawValue)"\#(lineAttribute(blockQuote))>"# + "\n"
        output += #"<p class="alert-title">\#(kind.title)</p>"# + "\n"
        tightListDepth.append(false)
        for (index, child) in blockQuote.children.enumerated() {
            guard index == 0, let paragraph = child as? Paragraph else {
                visit(child)
                continue
            }
            // The first paragraph loses its marker line; whatever follows it is the alert's first paragraph.
            let rest = Alert.inlinesAfterMarker(in: paragraph)
            guard !rest.isEmpty else { continue }
            let line =
                includesLines ? paragraph.range.map { #" data-line="\#($0.lowerBound.line + 1)""# } ?? "" : ""
            output += "<p\(line)>"
            for inline in rest { visit(inline) }
            output += "</p>\n"
        }
        tightListDepth.removeLast()
        output += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        // cmark keeps the line break before the closing fence; it would render as a blank last line.
        var code = Placeholder.restoringTeX(in: codeBlock.code, math: math)
        if code.hasSuffix("\n") { code.removeLast() }
        let language = codeBlock.language?.split(separator: " ").first.map(String.init)?.lowercased()
        if language == "mermaid" {
            features.insert(.mermaid)
            output += #"<div class="mermaid"\#(lineAttribute(codeBlock))>\#(escape(code))</div>"# + "\n"
            return
        }
        var classAttribute = ""
        if let language, !language.isEmpty {
            features.insert(.code)
            classAttribute = #" class="language-\#(escapeAttribute(language))""#
        }
        output += "<pre\(lineAttribute(codeBlock))><code\(classAttribute)>\(escape(code))</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        output += Placeholder.restoringTeX(in: html.rawHTML, math: math)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        output += "<hr\(lineAttribute(thematicBreak))>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        let isTask = list.listItems.contains { $0.checkbox != nil }
        let classAttribute = isTask ? #" class="contains-task-list""# : ""
        output += "<ul\(classAttribute)\(lineAttribute(list))>\n"
        visitListItems(of: list)
        output += "</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        let start = list.startIndex == 1 ? "" : #" start="\#(list.startIndex)""#
        output += "<ol\(start)\(lineAttribute(list))>\n"
        visitListItems(of: list)
        output += "</ol>\n"
    }

    private mutating func visitListItems(of list: ListItemContainer) {
        tightListDepth.append(isTight(list))
        descendInto(list)
        tightListDepth.removeLast()
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            output += #"<li class="task"\#(lineAttribute(listItem))><input type="checkbox" disabled\#(checked)> "#
        } else {
            output += "<li\(lineAttribute(listItem))>"
        }
        descendInto(listItem)
        if output.hasSuffix("\n"), tightListDepth.last == true, listItem.childCount == 1 { output.removeLast() }
        output += "</li>\n"
    }

    mutating func visitTable(_ table: Table) {
        tableAlignments = table.columnAlignments
        output += "<div class=\"table\"\(lineAttribute(table))>\n<table>\n"
        visit(table.head)
        // A table with only a header has no body (as cmark-gfm renders it).
        if !table.body.isEmpty {
            output += "<tbody>\n"
            visit(table.body)
            output += "</tbody>\n"
        }
        output += "</table>\n</div>\n"
    }

    mutating func visitTableHead(_ head: Table.Head) {
        inTableHead = true
        output += "<thead>\n<tr>"
        descendInto(head)
        output += "</tr>\n</thead>\n"
        inTableHead = false
    }

    mutating func visitTableRow(_ row: Table.Row) {
        output += "<tr>"
        descendInto(row)
        output += "</tr>\n"
    }

    mutating func visitTableCell(_ cell: Table.Cell) {
        let tag = inTableHead ? "th" : "td"
        var style = ""
        if cell.indexInParent < tableAlignments.count, let alignment = tableAlignments[cell.indexInParent] {
            switch alignment {
            case .left: style = #" style="text-align:left""#
            case .center: style = #" style="text-align:center""#
            case .right: style = #" style="text-align:right""#
            }
        }
        output += "<\(tag)\(style)>"
        descendInto(cell)
        output += "</\(tag)>"
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) {
        let string = text.string
        guard !footnotes.labels.isEmpty, linkDepth == 0, string.contains("[^") else {
            output += inline(string)
            return
        }
        var cursor = string.startIndex
        for match in string.matches(of: Footnotes.reference) {
            let label = match.output.1.lowercased()
            guard footnotes.labels.contains(label) else { continue }
            output += inline(String(string[cursor..<match.range.lowerBound]))
            let (number, id) = footnotes.reference(to: label)
            output += ##"<sup class="footnote-ref"><a href="#fn:\##(number)" id="\##(id)">\##(number)</a></sup>"##
            cursor = match.range.upperBound
        }
        output += inline(String(string[cursor...]))
    }

    /// Escaped text with math tokens turned into KaTeX placeholders.
    private func inline(_ text: String) -> String {
        Placeholder.replacing(in: escape(text), math: math) { span in
            let display = span.isDisplay ? " display" : ""
            return #"<span class="math\#(display)" data-tex="\#(escapeAttribute(span.tex))"></span>"#
        }
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) { wrap(emphasis, in: "em") }
    mutating func visitStrong(_ strong: Strong) { wrap(strong, in: "strong") }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) { wrap(strikethrough, in: "del") }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        output += "<code>\(escape(Placeholder.restoringTeX(in: inlineCode.code, math: math)))</code>"
    }

    mutating func visitLink(_ link: Link) {
        let title = link.title.map { #" title="\#(escapeAttribute($0))""# } ?? ""
        output += #"<a href="\#(escapeAttribute(link.destination ?? ""))"\#(title)>"#
        linkDepth += 1
        descendInto(link)
        linkDepth -= 1
        output += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        let alt = Placeholder.restoringTeX(in: image.plainText, math: math)
        let title = image.title.map { #" title="\#(escapeAttribute($0))""# } ?? ""
        output += #"<img src="\#(escapeAttribute(image.source ?? ""))" alt="\#(escapeAttribute(alt))"\#(title)>"#
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) { output += inlineHTML.rawHTML }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { output += "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { output += "<br>\n" }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        output += "<code>\(escape(symbolLink.destination ?? ""))</code>"
    }

    // MARK: Helpers

    private mutating func wrap(_ markup: Markup, in tag: String) {
        output += "<\(tag)>"
        descendInto(markup)
        output += "</\(tag)>"
    }

    /// A list is tight when no blank line separates its items or their blocks.
    private func isTight(_ list: ListItemContainer) -> Bool {
        var previousEnd: Int?
        for item in list.listItems {
            for child in item.children {
                guard let range = child.range else { continue }
                if let previousEnd, range.lowerBound.line > previousEnd + 1 { return false }
                previousEnd = range.upperBound.line
            }
        }
        return true
    }

    private func lineAttribute(_ markup: Markup) -> String {
        guard includesLines else { return "" }
        return markup.range.map { #" data-line="\#($0.lowerBound.line)""# } ?? ""
    }
}

func escape(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count)
    for character in text {
        switch character {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        case "\"": result += "&quot;"
        default: result.append(character)
        }
    }
    return result
}

func escapeAttribute(_ text: String) -> String {
    escape(text).replacingOccurrences(of: "\n", with: "&#10;")
}
