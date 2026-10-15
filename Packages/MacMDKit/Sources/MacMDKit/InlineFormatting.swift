import Foundation

/// A single text replacement plus the selection to apply afterwards (UTF-16 ranges).
public struct TextEdit: Hashable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// Toggling of inline Markdown formatting around a selection.
public enum InlineFormatting {
    public enum Style: Sendable {
        case strong, emphasis, strikethrough, inlineCode

        public var marker: String {
            switch self {
            case .strong: "**"
            case .emphasis: "*"
            case .strikethrough: "~~"
            case .inlineCode: "`"
            }
        }
    }

    public static func toggle(_ style: Style, in text: String, selection: NSRange) -> TextEdit {
        if style == .strong || style == .emphasis {
            return toggleAsterisks(style, in: text as NSString, selection: selection)
        }
        let source = text as NSString
        let marker = style.marker
        let length = (marker as NSString).length
        let selected = source.substring(with: selection)

        // Selection includes the markers: **bold** → bold
        if selection.length >= 2 * length, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(
                with: NSRange(location: length, length: selection.length - 2 * length))
            return TextEdit(
                range: selection, replacement: inner,
                selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }
        // Markers surround the selection: **[bold]** → bold
        let outer = NSRange(location: selection.location - length, length: selection.length + 2 * length)
        if outer.location >= 0, NSMaxRange(outer) <= source.length,
            source.substring(with: NSRange(location: outer.location, length: length)) == marker,
            source.substring(with: NSRange(location: NSMaxRange(selection), length: length)) == marker
        {
            return TextEdit(
                range: outer, replacement: selected,
                selection: NSRange(location: outer.location, length: selection.length))
        }
        return TextEdit(
            range: selection, replacement: marker + selected + marker,
            selection: NSRange(location: selection.location + length, length: selection.length))
    }

    /// Bold (`**`) and italic (`*`) share the asterisk, so they are toggled by counting asterisk runs:
    /// a run of 2 or 3 means bold, an odd run (1 or 3) means italic. Adding italic to bold gives `***x***`,
    /// and removing one keeps the other.
    private static func toggleAsterisks(_ style: Style, in source: NSString, selection: NSRange) -> TextEdit {
        let width = style == .strong ? 2 : 1
        func isApplied(_ run: Int) -> Bool { style == .strong ? run >= 2 : run % 2 == 1 }
        let selected = source.substring(with: selection)
        let selectedLength = (selected as NSString).length

        // The selection includes its asterisks: [**bold**]
        let leading = selected.prefix { $0 == "*" }.count
        let trailing = selected.reversed().prefix { $0 == "*" }.count
        let inside = min(leading, trailing)
        if inside > 0, inside * 2 < selectedLength {
            let inner = (selected as NSString).substring(
                with: NSRange(location: inside, length: selectedLength - 2 * inside))
            let markers = String(repeating: "*", count: isApplied(inside) ? inside - width : inside + width)
            let replacement = markers + inner + markers
            return TextEdit(
                range: selection, replacement: replacement,
                selection: NSRange(location: selection.location, length: (replacement as NSString).length))
        }

        // Asterisks surround the selection: **[bold]**
        var before = 0
        while selection.location - before > 0, source.character(at: selection.location - before - 1) == 0x2A {
            before += 1
        }
        var after = 0
        while NSMaxRange(selection) + after < source.length,
            source.character(at: NSMaxRange(selection) + after) == 0x2A
        {
            after += 1
        }
        if isApplied(min(before, after)) {
            let outer = NSRange(location: selection.location - width, length: selection.length + 2 * width)
            return TextEdit(
                range: outer, replacement: selected,
                selection: NSRange(location: outer.location, length: selection.length))
        }
        let marker = String(repeating: "*", count: width)
        return TextEdit(
            range: selection, replacement: marker + selected + marker,
            selection: NSRange(location: selection.location + width, length: selection.length))
    }

    /// Wraps the selection as `[selection](url)` and selects the `url` placeholder.
    public static func link(in text: String, selection: NSRange) -> TextEdit {
        let selected = (text as NSString).substring(with: selection)
        let label = selected.isEmpty ? "text" : selected
        let replacement = "[\(label)](url)"
        if selected.isEmpty {
            return TextEdit(
                range: selection, replacement: replacement,
                selection: NSRange(location: selection.location + 1, length: 4))
        }
        let urlLocation = selection.location + (label as NSString).length + 3
        return TextEdit(
            range: selection, replacement: replacement, selection: NSRange(location: urlLocation, length: 3))
    }
}
