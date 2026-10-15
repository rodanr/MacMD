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
        let (prepared, math) = MathExtractor.replacingWithPlaceholders(markdown)
        var visitor = HTMLVisitor(math: math)
        visitor.visit(MarkdownParser.parse(prepared))
        if !math.isEmpty { visitor.features.insert(.math) }
        return RenderedHTML(
            body: visitor.output.trimmingCharacters(in: .newlines),
            features: visitor.features)
    }
}

private struct HTMLVisitor: MarkupWalker {
    let math: [Int: MathSpan]
    var output = ""
    var features: RenderedHTML.Features = []
    private var slugger = Slugger()
    private var tightListDepth: [Bool] = []
    private var tableAlignments: [Table.ColumnAlignment?] = []
    private var inTableHead = false

    init(math: [Int: MathSpan]) { self.math = math }

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
        let slug = slugger.slug(HeadingTitle.plainText(of: heading, math: math))
        output += #"<h\#(heading.level) id="\#(escapeAttribute(slug))"\#(lineAttribute(heading))>"#
        descendInto(heading)
        output += "</h\(heading.level)>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        output += "<blockquote\(lineAttribute(blockQuote))>\n"
        tightListDepth.append(false)
        descendInto(blockQuote)
        tightListDepth.removeLast()
        output += "</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let code = Placeholder.restoringTeX(in: codeBlock.code, math: math)
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
        output += "<table\(lineAttribute(table))>\n"
        descendInto(table)
        output += "</tbody>\n</table>\n"
    }

    mutating func visitTableHead(_ head: Table.Head) {
        inTableHead = true
        output += "<thead>\n<tr>"
        descendInto(head)
        output += "</tr>\n</thead>\n<tbody>\n"
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
        output += Placeholder.replacing(in: escape(text.string), math: math) { span in
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
        descendInto(link)
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
        markup.range.map { #" data-line="\#($0.lowerBound.line)""# } ?? ""
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
