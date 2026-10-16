import AppKit
import MacMDKit

/// The editor: a TextKit 2 `NSTextView` with Markdown-aware editing behaviour.
///
/// Never touch `layoutManager` here — doing so silently downgrades the view to TextKit 1.
final class MarkdownTextView: NSTextView {
    /// Maximum width of the text column; `nil` fills the view.
    var maxContentWidth: CGFloat? = 720 { didSet { updateInsets() } }
    var isTypewriterMode = false {
        didSet {
            updateInsets()
            // Center right away so turning the mode on visibly does something.
            if isTypewriterMode { DispatchQueue.main.async { [weak self] in self?.centerCaret() } }
        }
    }
    var isFocusMode = false { didSet { updateFocusDimming() } }
    /// The paper color laid over dimmed text in focus mode.
    var focusShadeColor: NSColor = .textBackgroundColor
    weak var styleEngine: StyleEngine?

    // Vim mode (see MarkdownTextView+Vim.swift)
    var isVimEnabled = false { didSet { if oldValue != isVimEnabled { vimEnabledDidChange() } } }
    var vim: VimEngine?
    /// Reports the Vim status ("NORMAL", "INSERT", ":w", …) or nil when Vim mode is off.
    var onVimStatusChange: ((String?) -> Void)?
    /// The caret color for ordinary editing; normal mode hides the caret and draws a block instead.
    var caretColor: NSColor = .controlAccentColor { didSet { updateCaretAppearance() } }
    let blockCursor = BlockCursorView()
    /// True while the editor applies the engine's own actions, so selection changes aren't fed back.
    var isApplyingVim = false
    /// The document folder, used to build relative links for dropped or pasted images.
    var documentDirectory: URL?

    static let minimumHorizontalInset: CGFloat = 36
    static let verticalInset: CGFloat = 28

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
        updateBlockCursor()
        updateFocusDimming()
    }

    /// Called after restyling, which can move text under the block cursor and focus shades.
    func styleDidChange() {
        updateBlockCursor()
        updateFocusDimming()
        // A theme, zoom or font-size change restyles; the placeholder follows the new body font.
        if string.isEmpty { needsDisplay = true }
    }

    // MARK: Placeholder

    /// Shown in an empty document. Drawn only, never part of the text, so saving, undo and counts ignore it.
    var placeholder = "Start writing…" {
        didSet {
            setAccessibilityPlaceholderValue(placeholder)
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, isEditable, !hasMarkedText() else { return }
        var attributes = styleEngine?.styler.baseAttributes ?? typingAttributes
        let color = attributes[.foregroundColor] as? NSColor ?? textColor ?? .labelColor
        attributes[.foregroundColor] = color.withAlphaComponent(0.35)
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = textContainerOrigin
        let rect = NSRect(
            x: origin.x + padding, y: origin.y,
            width: max(bounds.width - origin.x * 2 - padding * 2, 0), height: bounds.height - origin.y)
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }

    private var wasEmpty = true

    /// Shows or hides the placeholder when the text becomes empty or stops being empty. Called for every
    /// character edit, including ones that bypass the text view (revert, external reload).
    func textStorageDidChangeCharacters() {
        let isEmpty = textStorage?.length == 0
        guard isEmpty != wasEmpty else { return }
        wasEmpty = isEmpty
        needsDisplay = true
    }

    override func didChangeText() {
        super.didChangeText()
        textStorageDidChangeCharacters()
    }

    private func updateInsets() {
        let width = enclosingScrollView?.contentSize.width ?? bounds.width
        let horizontal = max(
            Self.minimumHorizontalInset, ((width - (maxContentWidth ?? .greatestFiniteMagnitude)) / 2).rounded())
        let visibleHeight = enclosingScrollView?.contentSize.height ?? 0
        let bottom = isTypewriterMode ? max(visibleHeight / 2, Self.verticalInset) : Self.verticalInset * 3
        let inset = NSSize(width: horizontal, height: Self.verticalInset)
        if textContainerInset != inset {
            textContainerInset = inset
            // Without this the text keeps its old left edge until the window is resized.
            invalidateTextContainerOrigin()
            textLayoutManager?.textViewportLayoutController.layoutViewport()
            needsDisplay = true
        }
        // NSTextView applies the same inset top and bottom; extra bottom room comes from the container.
        if let scrollView = enclosingScrollView, scrollView.contentInsets.bottom != bottom - Self.verticalInset {
            scrollView.contentInsets.bottom = max(bottom - Self.verticalInset, 0)
        }
    }

    // MARK: Geometry (TextKit 2)

    func textRange(for range: NSRange) -> NSTextRange? {
        guard let contentManager = textLayoutManager?.textContentManager,
            let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
            let end = contentManager.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// The rect of a character range in view coordinates.
    func rect(for range: NSRange) -> NSRect? {
        guard let textLayoutManager, let textRange = textRange(for: range) else { return nil }
        textLayoutManager.ensureLayout(for: textRange)
        var result: NSRect?
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) {
            _, frame, _, _ in
            result = result.map { $0.union(frame) } ?? frame
            return true
        }
        return result?.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// 1-based line number at the top of the visible area.
    func topVisibleLine() -> Int {
        guard let textLayoutManager, let contentManager = textLayoutManager.textContentManager else { return 1 }
        let point = CGPoint(x: 0, y: visibleRect.minY - textContainerOrigin.y + 4)
        guard let fragment = textLayoutManager.textLayoutFragment(for: point) else { return 1 }
        let offset = contentManager.offset(
            from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
        return lineNumber(at: offset)
    }

    func lineNumber(at offset: Int) -> Int {
        TextMetrics.lineNumber(in: string, atUTF16Offset: offset)
    }

    func offset(ofLine line: Int) -> Int {
        let text = string as NSString
        var current = 1
        var location = 0
        while current < line, location < text.length {
            location = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
            current += 1
        }
        return min(location, text.length)
    }

    func scroll(toLine line: Int, select: Bool) {
        let location = offset(ofLine: line)
        if select {
            setSelectedRange(NSRange(location: location, length: 0))
            window?.makeFirstResponder(self)
        }
        guard let rect = rect(for: NSRange(location: location, length: 0)) else { return }
        let y = max(rect.minY - Self.verticalInset, 0)
        scroll(NSPoint(x: 0, y: y))
    }

    // MARK: Focus & typewriter

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        guard !stillSelectingFlag else { return }
        vimSelectionDidChange()
        updateFocusDimming()
        if isTypewriterMode { centerCaret() }
    }

    /// Focus mode dims everything but the current paragraph by covering it with translucent paper.
    /// Plain views always redraw, unlike TextKit 2 rendering attributes.
    private var focusShades: [FocusShadeView] {
        let existing = subviews.compactMap { $0 as? FocusShadeView }
        if existing.count == 2 { return existing }
        let shades = [FocusShadeView(), FocusShadeView()]
        shades.forEach { addSubview($0) }
        return shades
    }

    /// Keeps the lines the selection touches at full strength, or the nearest written paragraph when the caret
    /// is on a blank line (see `FocusParagraph`).
    func updateFocusDimming() {
        guard isFocusMode, let text = textStorage?.mutableString,
            let focus = FocusParagraph.range(in: text, selection: selectedRange()),
            let paragraph = layoutFragmentsFrame(for: focus)
        else {
            subviews.compactMap { $0 as? FocusShadeView }.forEach { $0.isHidden = true }
            return
        }
        let shades = focusShades
        shades[0].frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(paragraph.minY, 0))
        shades[1].frame = NSRect(
            x: 0, y: paragraph.maxY, width: bounds.width, height: max(bounds.height - paragraph.maxY, 0))
        shades.forEach {
            $0.color = focusShadeColor
            $0.isHidden = false
        }
    }

    /// The frames of the layout fragments (paragraphs) holding `range`, in view coordinates.
    ///
    /// TextKit 2 lays out lazily: a paragraph just typed or far down the document has no real frame until it
    /// is laid out, so this lays it out first.
    private func layoutFragmentsFrame(for range: NSRange) -> NSRect? {
        guard let textLayoutManager, let textRange = textRange(for: range) else { return nil }
        textLayoutManager.ensureLayout(for: textRange)
        var frame: NSRect?
        textLayoutManager.enumerateTextLayoutFragments(from: textRange.location, options: [.ensuresLayout]) {
            fragment in
            if frame != nil, fragment.rangeInElement.location.compare(textRange.endLocation) != .orderedAscending {
                return false
            }
            frame = frame.map { $0.union(fragment.layoutFragmentFrame) } ?? fragment.layoutFragmentFrame
            return true
        }
        guard let frame, frame.height > 0 else { return nil }
        return frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    /// Lines above a paragraph that was just laid out may still have estimated heights; laying those out moves
    /// the paragraph. Focus shades and typewriter centering follow it after every layout pass.
    override func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(controller)
        if isFocusMode { updateFocusDimming() }
        if isTypewriterMode, needsCaretCentering {
            needsCaretCentering = false
            scrollCaretToCenter()
        }
    }

    /// Set when the caret moves in typewriter mode, so the next layout pass centers it once more.
    private var needsCaretCentering = false

    func centerCaret() {
        needsCaretCentering = true
        scrollCaretToCenter()
    }

    private func scrollCaretToCenter() {
        guard let scrollView = enclosingScrollView,
            let caret = rect(for: NSRange(location: selectedRange().location, length: 0))
        else { return }
        let visible = scrollView.contentView.bounds
        let target = NSPoint(x: visible.minX, y: max(caret.midY - visible.height / 2, -scrollView.contentInsets.top))
        guard abs(target.y - visible.minY) > 1 else { return }
        scrollView.contentView.scroll(to: target)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Editing behaviour

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard !hasMarkedText(), selection.length == 0 else { return super.insertNewline(sender) }
        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let linePrefix = text.substring(
            with: NSRange(location: lineRange.location, length: selection.location - lineRange.location))

        if styleEngine?.isInsideCodeBlock(selection.location) == true {
            let indentation = linePrefix.prefix { $0 == " " || $0 == "\t" }
            return insertText("\n" + indentation, replacementRange: selection)
        }
        switch ListContinuation.forLine(linePrefix) {
        case .continue(let prefix):
            insertText("\n" + prefix, replacementRange: selection)
        case .terminate(let markerLength):
            let lineContent = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            if (lineContent as NSString).length > (linePrefix as NSString).length {
                super.insertNewline(sender)
            } else {
                replace(NSRange(location: lineRange.location, length: markerLength), with: "")
            }
        case .notAList:
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText(), isOnListLine() else { return super.insertTab(sender) }
        transformSelectedLines(ListContinuation.indented)
    }

    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText(), isOnListLine() else { return super.insertBacktab(sender) }
        transformSelectedLines(ListContinuation.outdented)
    }

    private static let wrappingPairs: [String: String] = [
        "*": "*", "_": "_", "`": "`", "~": "~", "\"": "\"", "(": ")", "[": "]", "=": "=",
    ]

    /// Typing a Markdown delimiter while text is selected wraps the selection instead of replacing it.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let selection = selectedRange()
        if !hasMarkedText(), replacementRange.location == NSNotFound, selection.length > 0,
            let typed = string as? String, let closing = Self.wrappingPairs[typed]
        {
            let selected = (self.string as NSString).substring(with: selection)
            apply(
                TextEdit(
                    range: selection, replacement: typed + selected + closing,
                    selection: NSRange(location: selection.location + 1, length: selection.length)))
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: Formatting commands (menu / shortcuts)

    @objc func toggleBold(_ sender: Any?) { toggle(.strong) }
    @objc func toggleItalic(_ sender: Any?) { toggle(.emphasis) }
    @objc func toggleStrikethrough(_ sender: Any?) { toggle(.strikethrough) }
    @objc func toggleInlineCode(_ sender: Any?) { toggle(.inlineCode) }

    @objc func insertLink(_ sender: Any?) {
        apply(InlineFormatting.link(in: string, selection: selectedRange()))
    }

    @objc func setHeadingLevel(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        transformSelectedLines { BlockFormatting.settingHeading(level: item.tag, line: $0) }
    }

    private func toggle(_ style: InlineFormatting.Style) {
        apply(InlineFormatting.toggle(style, in: string, selection: selectedRange()))
    }

    // MARK: Images

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = imageURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        let location = characterIndexForInsertion(at: point)
        insertImageLinks(for: urls, at: NSRange(location: location, length: 0))
        return true
    }

    /// A plain-text view disables Paste when the pasteboard holds only an image; enable it, since pasting
    /// an image saves it next to the document and inserts a link.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), isEditable, canPasteImages(from: .general) { return true }
        return super.validateUserInterfaceItem(item)
    }

    private func canPasteImages(from pasteboard: NSPasteboard) -> Bool {
        !imageURLs(from: pasteboard).isEmpty
            || (pasteboard.string(forType: .string) == nil && NSImage.canInit(with: pasteboard))
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let urls = imageURLs(from: pasteboard)
        if !urls.isEmpty {
            return insertImageLinks(for: urls, at: selectedRange())
        }
        if pasteboard.string(forType: .string) == nil, let image = NSImage(pasteboard: pasteboard),
            let url = savePastedImage(image)
        {
            return insertImageLinks(for: [url], at: selectedRange())
        }
        super.paste(sender)
    }

    private func imageURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"],
        ]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    private func insertImageLinks(for urls: [URL], at range: NSRange) {
        let links = urls.map { url in
            let path = documentDirectory.map { RelativePath.from($0, to: url) } ?? url.path
            let name = url.deletingPathExtension().lastPathComponent
            return "![\(name)](\(RelativePath.markdownEscaped(path)))"
        }
        replace(range, with: links.joined(separator: "\n"))
    }

    /// Saves a pasted bitmap next to the document (`assets/`), or returns nil for unsaved documents.
    private func savePastedImage(_ image: NSImage) -> URL? {
        guard let directory = documentDirectory?.appending(path: "assets", directoryHint: .isDirectory),
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            NSSound.beep()
            return nil
        }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        var url = directory.appending(path: "pasted-\(stamp).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appending(path: "pasted-\(stamp)-\(counter).png")
            counter += 1
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            presentError(error)
            return nil
        }
    }

    // MARK: Helpers

    private func isOnListLine() -> Bool {
        let text = string as NSString
        let line = text.substring(with: text.lineRange(for: NSRange(location: selectedRange().location, length: 0)))
        return ListContinuation.forLine(line.trimmingCharacters(in: .newlines)) != .notAList
    }

    /// Applies `transform` to each line touched by the selection as one undoable edit.
    private func transformSelectedLines(_ transform: (String) -> String) {
        let text = string as NSString
        let lines = text.lineRange(for: selectedRange())
        var parts: [(line: String, terminator: String)] = []
        text.enumerateSubstrings(in: lines, options: [.byLines]) { line, lineRange, enclosing, _ in
            let terminator = text.substring(
                with: NSRange(location: NSMaxRange(lineRange), length: NSMaxRange(enclosing) - NSMaxRange(lineRange)))
            parts.append((line ?? "", terminator))
        }
        let replacement = parts.map { transform($0.line) + $0.terminator }.joined()
        let caretOffset =
            selectedRange().length == 0
            ? (replacement as NSString).length - (text.substring(with: lines) as NSString).length : 0
        let newSelection =
            selectedRange().length == 0
            ? NSRange(location: max(selectedRange().location + caretOffset, lines.location), length: 0)
            : NSRange(location: lines.location, length: (replacement as NSString).length)
        apply(TextEdit(range: lines, replacement: replacement, selection: newSelection))
    }

    private func replace(_ range: NSRange, with replacement: String) {
        apply(
            TextEdit(
                range: range, replacement: replacement,
                selection: NSRange(location: range.location + (replacement as NSString).length, length: 0)))
    }

    /// Performs an edit through the text system so it is undoable and notifies delegates.
    func apply(_ edit: TextEdit) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(
            in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: typingAttributes))
        didChangeText()
        setSelectedRange(edit.selection)
    }
}

/// Translucent paper over the text outside the focused paragraph.
final class FocusShadeView: NSView {
    /// How much of the paper covers dimmed text: 0.45 leaves it at about 55 % strength, quiet but readable.
    static let opacity: CGFloat = 0.45

    var color: NSColor = .textBackgroundColor { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Views don't clip by default (macOS 14+), and `dirtyRect` can reach past the bounds, over the focused
        // paragraph; fill only the bounds.
        color.withAlphaComponent(Self.opacity).setFill()
        dirtyRect.intersection(bounds).fill()
    }
}
