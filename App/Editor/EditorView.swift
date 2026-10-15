import AppKit
import SwiftUI

/// SwiftUI wrapper around the TextKit 2 editor.
struct EditorView: NSViewRepresentable {
    let model: DocumentModel
    let theme: Theme
    let lineWidth: CGFloat?
    let spellChecking: Bool
    let isFocusMode: Bool
    let isTypewriterMode: Bool
    let isVimEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let layoutManager = NSTextLayoutManager()
        layoutManager.delegate = context.coordinator
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container

        let contentStorage = NSTextContentStorage()
        contentStorage.textStorage = model.textStorage
        contentStorage.addTextLayoutManager(layoutManager)
        context.coordinator.contentStorage = contentStorage

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.documentDirectory = model.fileURL?.deletingLastPathComponent()
        textView.setAccessibilityIdentifier("editor")
        textView.setAccessibilityPlaceholderValue(textView.placeholder)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.automaticallyAdjustsContentInsets = true

        let engine = StyleEngine(storage: model.textStorage, textView: textView, theme: theme)
        context.coordinator.engine = engine
        textView.styleEngine = engine
        model.editor = textView
        textView.onVimStatusChange = { [weak model] in model?.vimStatus = $0 }
        configure(textView, scrollView: scrollView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        configure(textView, scrollView: scrollView, coordinator: context.coordinator)
    }

    private func configure(_ textView: MarkdownTextView, scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.palette = DecorationPalette(
            codeBackground: theme.codeBackground, quoteBar: theme.quoteBar, rule: theme.rule)
        coordinator.engine?.theme = theme
        textView.backgroundColor = theme.background
        scrollView.backgroundColor = theme.background
        textView.caretColor = theme.accent
        textView.focusShadeColor = theme.background
        textView.maxContentWidth = lineWidth
        textView.isContinuousSpellCheckingEnabled = spellChecking
        textView.documentDirectory = model.fileURL?.deletingLastPathComponent()
        textView.isEditable = model.mode == .edit
        if textView.isFocusMode != isFocusMode { textView.isFocusMode = isFocusMode }
        if textView.isTypewriterMode != isTypewriterMode { textView.isTypewriterMode = isTypewriterMode }
        textView.isVimEnabled = isVimEnabled
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextLayoutManagerDelegate {
        let model: DocumentModel
        var engine: StyleEngine?
        var contentStorage: NSTextContentStorage?
        /// Read from the layout delegate callback, which TextKit invokes on the main thread.
        nonisolated(unsafe) var palette = DecorationPalette()
        private var caretUpdate: Task<Void, Never>?

        init(model: DocumentModel) { self.model = model }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }
            // Keyboard navigation can change the selection without the view's setter seeing the final value.
            textView.updateFocusDimming()
            caretUpdate?.cancel()
            caretUpdate = Task { [weak self, weak textView] in
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled, let self, let textView else { return }
                let text = textView.string as NSString
                let location = min(textView.selectedRange().location, text.length)
                let lineStart = text.lineRange(for: NSRange(location: location, length: 0)).location
                self.model.caretLine = textView.lineNumber(at: location)
                self.model.caretColumn = location - lineStart + 1
            }
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            view.window?.windowController?.document?.undoManager ?? view.window?.undoManager
        }

        nonisolated func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            if let paragraph = textElement as? NSTextParagraph,
                paragraph.attributedString.length > 0,
                let raw = paragraph.attributedString.attribute(.blockDecoration, at: 0, effectiveRange: nil) as? String,
                let decoration = BlockDecoration(rawValue: raw)
            {
                return DecoratedLayoutFragment(
                    textElement: textElement, range: textElement.elementRange, decoration: decoration, palette: palette)
            }
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
    }
}
