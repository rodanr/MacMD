import AppKit
import MacMDKit

/// Vim mode: keys go through `VimEngine`, and its actions are applied with the editor's own undoable
/// edits, so undo, autosave, styling and spell checking work as usual.
extension MarkdownTextView {
    override func keyDown(with event: NSEvent) {
        guard var engine = vim, isEditable, !hasMarkedText(), let key = VimKey(event: event) else {
            return super.keyDown(with: event)
        }
        let actions = engine.handle(key, text: document, selection: selectedRange())
        vim = engine
        perform(actions, event: event)
    }

    private var document: NSString { textStorage?.mutableString ?? "" }

    func perform(_ actions: [VimAction], event: NSEvent?) {
        let wasApplying = isApplyingVim
        isApplyingVim = true
        defer {
            isApplyingVim = wasApplying
            vimDidUpdate()
        }
        breakUndoCoalescing()
        for action in actions {
            switch action {
            case .passThrough:
                guard let event else { continue }
                isApplyingVim = wasApplying
                super.keyDown(with: event)
                isApplyingVim = true
            case .replace(let range, let replacement):
                guard NSMaxRange(range) <= document.length else { continue }
                let caret = NSRange(location: range.location + (replacement as NSString).length, length: 0)
                apply(TextEdit(range: range, replacement: replacement, selection: caret))
            case .select(let range):
                let clamped = NSIntersectionRange(range, NSRange(location: 0, length: document.length))
                setSelectedRange(
                    range.length == 0 ? NSRange(location: min(range.location, document.length), length: 0) : clamped)
                scrollRangeToVisible(selectedRange())
            case .moveDisplayLines(let lines):
                moveCursor(byDisplayLines: lines)
            case .scrollHalfPage(let down):
                let lineHeight = max(font?.boundingRectForFont.height ?? 20, 1)
                let lines = max(Int(visibleRect.height / lineHeight / 2), 1)
                moveCursor(byDisplayLines: down ? lines : -lines)
            case .centerCursor:
                centerCaret()
            case .undo, .redo:
                guard let undoManager, action == .undo ? undoManager.canUndo : undoManager.canRedo else {
                    NSSound.beep()
                    continue
                }
                action == .undo ? undoManager.undo() : undoManager.redo()
                // Undo selects the restored text; Vim leaves a cursor instead.
                collapseToVimCursor()
            case .save:
                NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: self)
            case .close:
                window?.performClose(nil)
            case .replay(let keys):
                guard var engine = vim else { continue }
                engine.isReplaying = true
                vim = engine
                for key in keys {
                    guard var current = vim else { break }
                    let replayed = current.handle(key, text: document, selection: selectedRange())
                    vim = current
                    perform(replayed, event: nil)
                }
                vim?.isReplaying = false
            case .beep:
                NSSound.beep()
            }
        }
        breakUndoCoalescing()
    }

    private func moveCursor(byDisplayLines lines: Int) {
        guard var engine = vim else { return }
        setSelectedRange(NSRange(location: engine.visualCursorPosition ?? selectedRange().location, length: 0))
        for _ in 0..<abs(lines) {
            if lines > 0 { moveDown(nil) } else { moveUp(nil) }
        }
        let actions = engine.cursorMoved(to: selectedRange().location, text: document)
        vim = engine
        perform(actions, event: nil)
    }

    private func collapseToVimCursor() {
        guard var engine = vim else { return }
        let actions = engine.reset(text: document, selection: NSRange(location: selectedRange().location, length: 0))
        vim = engine
        perform(actions, event: nil)
    }

    /// A click or drag changed the selection: let the engine adopt it (a drag starts visual mode).
    func vimSelectionDidChange() {
        guard !isApplyingVim, var engine = vim else {
            updateBlockCursor()
            return
        }
        let actions = engine.selectionChanged(to: selectedRange(), text: document)
        vim = engine
        perform(actions, event: nil)
    }

    func vimEnabledDidChange() {
        if isVimEnabled {
            vim = VimEngine()
            collapseToVimCursor()
        } else {
            vim = nil
            vimDidUpdate()
        }
    }

    private func vimDidUpdate() {
        updateCaretAppearance()
        updateBlockCursor()
        onVimStatusChange?(vim?.statusText)
    }

    func updateCaretAppearance() {
        let color: NSColor = vim?.usesBlockCursor == true ? .clear : caretColor
        if insertionPointColor != color { insertionPointColor = color }
    }

    func updateBlockCursor() {
        guard let engine = vim, engine.usesBlockCursor, window != nil else {
            blockCursor.isHidden = true
            return
        }
        if blockCursor.superview !== self { addSubview(blockCursor) }
        let text = document
        let location = min(engine.visualCursorPosition ?? selectedRange().location, text.length)
        let onCharacter =
            location < text.length && text.character(at: location) != 0x0A && text.character(at: location) != 0x0D
        let range =
            onCharacter ? text.rangeOfComposedCharacterSequence(at: location) : NSRange(location: location, length: 0)
        guard var frame = rect(for: range) ?? rect(for: NSRange(location: location, length: 0)) else {
            blockCursor.isHidden = true
            return
        }
        if frame.width < 2 { frame.size.width = max((font?.pointSize ?? 16) * 0.55, 6) }
        blockCursor.color = caretColor
        blockCursor.frame = frame
        blockCursor.isHidden = false
    }
}

/// The normal-mode cursor: a translucent block over the character, which stays readable.
final class BlockCursorView: NSView {
    var color: NSColor = .controlAccentColor { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
    }
}

extension VimKey {
    /// Translates a key press. Returns nil for ⌘ shortcuts and keys Vim mode leaves to the system.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { return nil }
        if event.keyCode == 53 {
            self = .escape
            return
        }
        if let special = event.specialKey {
            switch special {
            case .carriageReturn, .enter, .newline: self = .enter
            case .delete, .backspace: self = .backspace
            case .tab where !flags.contains(.shift): self = .tab
            case .leftArrow: self = .left
            case .rightArrow: self = .right
            case .upArrow: self = .up
            case .downArrow: self = .down
            default: return nil
            }
            return
        }
        if flags.contains(.control) {
            guard let char = event.charactersIgnoringModifiers?.lowercased().first else { return nil }
            self = char == "[" ? .escape : .ctrl(char)
            return
        }
        guard let characters = event.characters, characters.count == 1, let char = characters.first else { return nil }
        self = .char(char)
    }
}
