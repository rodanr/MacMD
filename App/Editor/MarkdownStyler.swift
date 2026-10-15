import AppKit
import MacMDKit

/// Maps `StyleSpan`s to text attributes for a theme. Only attributes change — never
/// characters — so styling is invisible to undo and to the document's dirty state.
@MainActor
final class MarkdownStyler {
    var theme: Theme {
        didSet { baseAttributes = Self.baseAttributes(for: theme) }
    }

    /// Attributes of plain body text for the current theme.
    private(set) var baseAttributes: [NSAttributedString.Key: Any]

    /// Signatures of blocks styled by the last pass (multiset), used to skip unchanged blocks.
    private(set) var appliedSignatures: [Int: Int] = [:]

    init(theme: Theme) {
        self.theme = theme
        self.baseAttributes = Self.baseAttributes(for: theme)
    }

    private static func baseAttributes(for theme: Theme) -> [NSAttributedString.Key: Any] {
        [.font: theme.bodyFont, .foregroundColor: theme.text, .paragraphStyle: paragraphStyle(theme: theme)]
    }

    /// Applies `result` to `storage`. Blocks are restyled when they intersect `dirty`,
    /// when their signature is new, or always when `full` is true.
    func apply(_ result: StyleResult, to storage: NSTextStorage, dirty: NSRange?, full: Bool) {
        let length = storage.length
        var previous = full ? [:] : appliedSignatures
        var current: [Int: Int] = [:]
        // Edits change the layout of the lines touching them, including the line right after an inserted line
        // break and the line before a deleted one, so those count as changed too.
        let dirtyParagraphs = dirty.map { range -> NSRange in
            let clamped = clamp(range, to: length)
            let lower = max(clamped.location - 1, 0)
            let upper = min(NSMaxRange(clamped) + 1, length)
            return (storage.string as NSString).paragraphRange(for: NSRange(location: lower, length: upper - lower))
        }

        storage.beginEditing()
        let text = storage.string as NSString
        var cursor = 0
        var previousRestyled = full
        for block in result.blocks {
            let range = clamp(block.range, to: length)
            // Text just before this block was rewritten (a gap reset, or the previous block restyled).
            var touchedBefore = previousRestyled
            if range.location > cursor {
                let gap = NSRange(location: cursor, length: range.location - cursor)
                // Gaps (blank lines, terminators) only need a reset next to changed text.
                if full || previousRestyled || intersects(gap, dirtyParagraphs) {
                    resetGap(gap, in: storage)
                    touchedBefore = true
                } else {
                    touchedBefore = false
                }
            }
            // A line takes its layout (indents, spacing) from its first character. When that character sits
            // before this block, as in an indented list item, rewriting it changed this block's line too.
            let sharesRewrittenLine =
                touchedBefore && range.location > 0 && !isLineBreak(text.character(at: range.location - 1))
            current[block.signature, default: 0] += 1
            if !sharesRewrittenLine, let count = previous[block.signature], count > 0,
                !intersects(range, dirtyParagraphs)
            {
                previous[block.signature] = count - 1
                previousRestyled = false
            } else {
                style(block, range: range, in: storage)
                previousRestyled = true
            }
            cursor = max(cursor, NSMaxRange(range))
        }
        if cursor < length {
            let tail = NSRange(location: cursor, length: length - cursor)
            if full || previousRestyled || intersects(tail, dirtyParagraphs) { resetGap(tail, in: storage) }
        }
        storage.endEditing()
        appliedSignatures = current
    }

    /// Styles a large document with base attributes only.
    func applyPlain(to storage: NSTextStorage) {
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        appliedSignatures = [:]
    }

    // MARK: Block styling

    private func resetGap(_ range: NSRange, in storage: NSTextStorage) {
        storage.setAttributes(baseAttributes, range: range)
    }

    private func style(_ block: StyledBlock, range: NSRange, in storage: NSTextStorage) {
        storage.setAttributes(baseAttributes, range: range)
        let spans = block.spans.sorted { priority($0.kind) < priority($1.kind) }
        for span in spans {
            // Stay inside the block: text beyond it belongs to other blocks, which restyle themselves.
            let spanRange = NSIntersectionRange(clamp(span.range, to: storage.length), range)
            guard spanRange.length > 0 else { continue }
            apply(span.kind, to: spanRange, in: storage)
        }
    }

    private func apply(_ kind: StyleKind, to range: NSRange, in storage: NSTextStorage) {
        switch kind {
        case .heading(let level):
            storage.addAttributes(
                [
                    .font: theme.headingFont(level: level),
                    .paragraphStyle: paragraphStyle(spacingBefore: theme.fontSize * (level <= 2 ? 1.1 : 0.7)),
                ],
                range: range)
        case .strong:
            addTraits(.bold, to: range, in: storage)
        case .emphasis:
            addTraits(.italic, to: range, in: storage)
        case .strikethrough:
            storage.addAttributes(
                [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: theme.secondaryText],
                range: range)
        case .inlineCode:
            storage.addAttributes([.font: theme.codeFont, .backgroundColor: theme.codeBackground], range: range)
        case .codeBlock:
            styleCodeBlock(range, in: storage)
        case .link:
            storage.addAttribute(.foregroundColor, value: theme.link, range: range)
        case .image:
            storage.addAttribute(.foregroundColor, value: theme.link.withAlphaComponent(0.8), range: range)
        case .blockQuote:
            let style = paragraphStyle(indent: 16)
            storage.addAttributes(
                [
                    .foregroundColor: theme.secondaryText, .paragraphStyle: style,
                    .blockDecoration: BlockDecoration.quote.rawValue,
                ],
                range: range)
        case .listMarker:
            storage.addAttribute(.foregroundColor, value: theme.listMarker, range: range)
            hangIndent(afterMarker: range, in: storage)
        case .taskBox(let checked):
            storage.addAttributes([.font: theme.codeFont, .foregroundColor: theme.listMarker], range: range)
            if checked {
                let line = (storage.string as NSString).lineRange(for: range)
                let rest = NSRange(location: NSMaxRange(range), length: NSMaxRange(line) - NSMaxRange(range))
                storage.addAttributes(
                    [.foregroundColor: theme.secondaryText, .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                    range: rest)
            }
        case .thematicBreak:
            storage.addAttributes(
                [.foregroundColor: theme.syntaxMarker, .blockDecoration: BlockDecoration.rule.rawValue], range: range)
        case .table:
            storage.addAttribute(.font, value: theme.codeFont, range: range)
        case .html:
            storage.addAttributes([.font: theme.codeFont, .foregroundColor: theme.secondaryText], range: range)
        case .math:
            storage.addAttributes([.font: theme.codeFont, .foregroundColor: theme.mathColor], range: range)
        case .syntaxMarker:
            storage.addAttribute(.foregroundColor, value: theme.syntaxMarker, range: range)
        }
    }

    private func styleCodeBlock(_ range: NSRange, in storage: NSTextStorage) {
        let text = storage.string as NSString
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            lines.append(NSIntersectionRange(enclosing, range))
        }
        let style = paragraphStyle(indent: 14, tailIndent: -14, spacing: 0)
        storage.addAttributes([.font: theme.codeFont, .paragraphStyle: style], range: range)
        for (index, line) in lines.enumerated() {
            // Include the line terminator so the decoration covers the whole paragraph.
            let paragraph = text.paragraphRange(for: NSRange(location: line.location, length: 0))
            storage.addAttribute(
                .blockDecoration, value: BlockDecoration.code(line: index, of: lines.count).rawValue,
                range: NSIntersectionRange(
                    paragraph, NSRange(location: range.location, length: NSMaxRange(paragraph) - range.location)))
        }
    }

    /// Wrapped lines of a list item align with the text after its marker.
    private func hangIndent(afterMarker marker: NSRange, in storage: NSTextStorage) {
        let text = storage.string as NSString
        let line = text.lineRange(for: marker)
        let prefix = NSRange(location: line.location, length: NSMaxRange(marker) - line.location)
        let width = (text.substring(with: prefix) as NSString).size(withAttributes: [.font: theme.bodyFont]).width
        let current = storage.attribute(.paragraphStyle, at: marker.location, effectiveRange: nil) as? NSParagraphStyle
        let style = (current ?? paragraphStyle()).mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = style.firstLineHeadIndent + width
        storage.addAttribute(.paragraphStyle, value: style, range: line)
    }

    private func addTraits(_ traits: NSFontDescriptor.SymbolicTraits, to range: NSRange, in storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? theme.bodyFont
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            if let styled = NSFont(descriptor: descriptor, size: font.pointSize) {
                storage.addAttribute(.font, value: styled, range: subrange)
            }
        }
    }

    // MARK: Helpers

    func paragraphStyle(
        indent: CGFloat = 0, tailIndent: CGFloat = 0, spacing: CGFloat? = nil, spacingBefore: CGFloat = 0
    ) -> NSParagraphStyle {
        Self.paragraphStyle(
            theme: theme, indent: indent, tailIndent: tailIndent, spacing: spacing, spacingBefore: spacingBefore)
    }

    private static func paragraphStyle(
        theme: Theme, indent: CGFloat = 0, tailIndent: CGFloat = 0, spacing: CGFloat? = nil, spacingBefore: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineHeightMultiple
        style.paragraphSpacing = spacing ?? theme.fontSize * 0.12
        style.paragraphSpacingBefore = spacingBefore
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.tailIndent = tailIndent
        return style
    }

    private func priority(_ kind: StyleKind) -> Int {
        switch kind {
        case .codeBlock, .blockQuote, .table, .thematicBreak, .html: 0
        case .heading: 1
        case .link, .image, .strong, .emphasis, .strikethrough: 2
        case .inlineCode, .math: 3
        case .listMarker, .taskBox: 4
        case .syntaxMarker: 5
        }
    }

    private func isLineBreak(_ unit: unichar) -> Bool { unit == 0x0A || unit == 0x0D }

    private func intersects(_ range: NSRange, _ dirty: NSRange?) -> Bool {
        guard let dirty else { return false }
        return NSIntersectionRange(range, dirty).length > 0 || range.location == dirty.location
            || NSLocationInRange(dirty.location, NSRange(location: range.location, length: range.length + 1))
    }

    private func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }
}
