import AppKit
import MacMDKit

/// Keeps the editor's attributes in sync with its text.
///
/// Parsing runs off the main actor; results are tagged with a generation number and
/// dropped if the text changed in the meantime. Styling is deferred while the input
/// method has marked text, because changing attributes mid-composition breaks IMEs.
@MainActor
final class StyleEngine {
    /// Documents larger than this (UTF-16 units) are restyled after a short pause instead of instantly.
    static let debounceThreshold = 50_000

    let styler: MarkdownStyler
    private let storage: NSTextStorage
    private weak var textView: NSTextView?
    private var generation = 0
    private var dirty: NSRange?
    private var needsFullPass = true
    /// Whether the document is currently shown unstyled because it is too large.
    private var isPlain = false
    private var task: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(storage: NSTextStorage, textView: NSTextView, theme: Theme) {
        self.storage = storage
        self.textView = textView
        self.styler = MarkdownStyler(theme: theme)
        observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { [weak self] notification in
            guard let storage = notification.object as? NSTextStorage,
                storage.editedMask.contains(.editedCharacters)
            else { return }
            let edited = storage.editedRange
            let delta = storage.changeInLength
            MainActor.assumeIsolated { self?.storageDidEdit(edited, delta: delta) }
        }
        restyleAll()
    }

    isolated deinit {
        task?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var theme: Theme {
        get { styler.theme }
        set {
            guard newValue != styler.theme else { return }
            styler.theme = newValue
            restyleAll()
        }
    }

    func restyleAll() {
        needsFullPass = true
        schedule(immediately: true)
    }

    /// The range most recently styled as code, for editing commands that behave differently there.
    func isInsideCodeBlock(_ location: Int) -> Bool {
        guard storage.length > 0 else { return false }
        let index = min(max(location - 1, 0), storage.length - 1)
        let value = storage.attribute(.blockDecoration, at: index, effectiveRange: nil) as? String
        return value.flatMap(BlockDecoration.init(rawValue:))?.isCode ?? false
    }

    /// Typing continues with the style of the character before the caret.
    private func refreshTypingAttributes() {
        guard let textView else { return }
        let caret = textView.selectedRange().location
        textView.typingAttributes =
            caret > 0 && caret <= storage.length
            ? storage.attributes(at: caret - 1, effectiveRange: nil) : styler.baseAttributes
    }

    private func storageDidEdit(_ edited: NSRange, delta: Int) {
        if var current = dirty {
            // Shift the pending dirty range by the edit, then merge.
            if current.location >= edited.location { current.location = max(current.location + delta, edited.location) }
            dirty = NSUnionRange(current, edited)
        } else {
            dirty = edited
        }
        schedule(immediately: storage.length < Self.debounceThreshold)
    }

    private func schedule(immediately: Bool) {
        generation += 1
        let expected = generation
        task?.cancel()
        task = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled, let self else { return }
            await self.run(expected)
        }
    }

    private func run(_ expected: Int) async {
        if textView?.hasMarkedText() == true { return }
        if storage.length > DocumentModel.largeDocumentThreshold {
            if needsFullPass || !isPlain { styler.applyPlain(to: storage) }
            isPlain = true
            needsFullPass = false
            dirty = nil
            return
        }
        if isPlain {
            // Dropped back under the threshold: style everything again.
            isPlain = false
            needsFullPass = true
        }
        let full = needsFullPass
        let text = storage.string
        let result = await Task.detached(priority: .userInitiated) { SpanCollector.collect(text) }.value
        guard expected == generation, !Task.isCancelled, textView?.hasMarkedText() != true else { return }
        styler.apply(result, to: storage, dirty: dirty, full: full)
        refreshTypingAttributes()
        (textView as? MarkdownTextView)?.styleDidChange()
        needsFullPass = false
        dirty = nil
    }
}
