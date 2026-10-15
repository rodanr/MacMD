import Foundation

/// A Vim keyboard interpreter. It holds no text: every call receives the current document and selection
/// and returns `VimAction`s for the editor to apply, which keeps the editor's undo, autosave and styling
/// in charge of the text.
public struct VimEngine: Sendable {
    public private(set) var mode: VimMode = .normal
    /// A one-off message such as "Pattern not found", shown until the next key.
    public private(set) var message: String?
    /// Set by the editor while it replays the `.` command.
    public var isReplaying = false

    private var pending: [VimKey] = []
    private var register = Register()
    private var lastFind: (target: Character, forward: Bool, till: Bool)?
    private var lastSearch: (pattern: String, forward: Bool, wholeWord: Bool)?
    private var visualAnchor = 0
    private var visualCursor = 0
    /// Keys of a change still in progress (one that entered insert mode).
    private var recording: [VimKey]?
    private var lastChange: [VimKey] = []

    private struct Register {
        var text = ""
        var linewise = false
    }

    public init() {}

    public var statusText: String {
        if let message { return message }
        switch mode {
        case .normal: return pending.isEmpty ? "NORMAL" : "NORMAL  " + pending.map(Self.describe).joined()
        case .insert: return "INSERT"
        case .visual: return "VISUAL"
        case .visualLine: return "VISUAL LINE"
        case .commandLine(let prompt, let text): return "\(prompt)\(text)"
        }
    }

    /// The moving end of the selection in visual mode (the anchor is the other end).
    public var visualCursorPosition: Int? { isVisual ? visualCursor : nil }

    /// Normal and visual modes draw a block cursor.
    public var usesBlockCursor: Bool {
        switch mode {
        case .normal, .visual, .visualLine: true
        case .insert, .commandLine: false
        }
    }

    // MARK: Entry points

    public mutating func handle(_ key: VimKey, text: NSString, selection: NSRange) -> [VimAction] {
        let document = VimText(text)
        message = nil
        switch mode {
        case .insert: return handleInsert(key, document, selection)
        case .commandLine(let prompt, let input): return handleCommandLine(key, prompt, input, document, selection)
        case .normal, .visual, .visualLine: return handleCommand(key, document, selection)
        }
    }

    /// Back to normal mode with the cursor on a character (when Vim mode is switched on).
    public mutating func reset(text: NSString, selection: NSRange) -> [VimAction] {
        mode = .normal
        pending = []
        recording = nil
        return [.select(NSRange(location: VimText(text).clampNormal(selection.location), length: 0))]
    }

    /// The editor moved the cursor for a `moveDisplayLines` or `scrollHalfPage` action.
    public mutating func cursorMoved(to position: Int, text: NSString) -> [VimAction] {
        let document = VimText(text)
        if isVisual {
            visualCursor = min(position, max(document.length - 1, 0))
            return [.select(visualRange(document))]
        }
        return [.select(NSRange(location: document.clampNormal(position), length: 0))]
    }

    /// The selection changed outside the engine, for example by a mouse click or drag.
    public mutating func selectionChanged(to selection: NSRange, text: NSString) -> [VimAction] {
        let document = VimText(text)
        switch mode {
        case .insert, .commandLine:
            return []
        case .visual, .visualLine:
            if selection == visualRange(document) { return [] }
            if selection.length == 0 {
                mode = .normal
                return clampCursor(selection.location, document)
            }
        case .normal:
            if selection.length == 0 { return clampCursor(selection.location, document) }
        }
        mode = .visual
        visualAnchor = selection.location
        visualCursor = document.previous(NSMaxRange(selection))
        return []
    }

    private func clampCursor(_ position: Int, _ document: VimText) -> [VimAction] {
        let clamped = document.clampNormal(position)
        return clamped == position ? [] : [.select(NSRange(location: clamped, length: 0))]
    }

    // MARK: Insert and command-line modes

    private mutating func handleInsert(_ key: VimKey, _ document: VimText, _ selection: NSRange) -> [VimAction] {
        if !isReplaying { recording?.append(key) }
        switch key {
        case .escape, .ctrl("["):
            mode = .normal
            if !isReplaying, let keys = recording { lastChange = keys }
            recording = nil
            let position = selection.location
            let target = position > document.lineStart(position) ? document.previous(position) : position
            return [.select(NSRange(location: document.clampNormal(target), length: 0))]
        default:
            guard isReplaying else { return [.passThrough] }
            switch key {
            case .char(let char): return [.replace(selection, with: String(char))]
            case .enter: return [.replace(selection, with: "\n")]
            case .tab: return [.replace(selection, with: "\t")]
            case .backspace:
                let start = document.previous(selection.location)
                return [.replace(NSRange(start..<selection.location), with: "")]
            default: return []
            }
        }
    }

    private mutating func handleCommandLine(
        _ key: VimKey, _ prompt: Character, _ input: String, _ document: VimText, _ selection: NSRange
    ) -> [VimAction] {
        switch key {
        case .char(let char):
            mode = .commandLine(prompt: prompt, text: input + String(char))
            return []
        case .backspace:
            mode = input.isEmpty ? .normal : .commandLine(prompt: prompt, text: String(input.dropLast()))
            return []
        case .escape, .ctrl("["):
            mode = .normal
            return []
        case .enter:
            mode = .normal
            return prompt == ":"
                ? runEx(input, document) : runSearch(input, forward: prompt == "/", document, selection)
        default:
            return []
        }
    }

    private mutating func runEx(_ input: String, _ document: VimText) -> [VimAction] {
        let command = input.trimmingCharacters(in: .whitespaces)
        switch command {
        case "": return []
        case "w", "w!": return [.save]
        case "q", "q!", "qa", "qa!": return [.close]
        case "wq", "wq!", "x", "x!": return [.save, .close]
        default:
            if let line = Int(command) {
                let start = document.lineStart(forLine: max(line, 1) - 1)
                return [.select(NSRange(location: document.clampNormal(document.firstNonBlank(start)), length: 0))]
            }
            message = "Unknown command: \(command)"
            return [.beep]
        }
    }

    private mutating func runSearch(
        _ input: String, forward: Bool, _ document: VimText, _ selection: NSRange
    ) -> [VimAction] {
        let pattern = input.isEmpty ? lastSearch?.pattern ?? "" : input
        lastSearch = (pattern, forward, false)
        guard let match = document.search(pattern, from: selection.location, forward: forward, wholeWord: false)
        else {
            message = pattern.isEmpty ? nil : "Pattern not found: \(pattern)"
            return [.beep]
        }
        return [.select(NSRange(location: match, length: 0))]
    }

    // MARK: Normal and visual modes

    private var isVisual: Bool { mode == .visual || mode == .visualLine }

    private mutating func handleCommand(_ key: VimKey, _ document: VimText, _ selection: NSRange) -> [VimAction] {
        pending.append(key)
        switch VimCommand.parse(pending, visual: isVisual) {
        case .incomplete:
            return []
        case .invalid:
            pending = []
            return [.beep]
        case .complete(let command):
            let keys = pending
            pending = []
            let cursor = isVisual ? visualCursor : document.clampNormal(selection.location)
            let wasNormal = mode == .normal
            let actions = execute(command, cursor: cursor, document)
            if wasNormal, !isReplaying, command.isChange {
                if mode == .insert { recording = keys } else { lastChange = keys }
            }
            return actions
        }
    }

    private mutating func execute(_ command: VimCommand, cursor: Int, _ document: VimText) -> [VimAction] {
        let count = command.count ?? 1
        switch command.action {
        case .simple(let simple):
            return isVisual
                ? visualCommand(simple, count: count, document) : simpleCommand(simple, command, cursor, document)
        case .wholeLines:
            guard let last = lastLine(from: cursor, count: count, document) else { return [.beep] }
            let range = NSRange(document.lineStart(cursor)..<document.lineEnd(last))
            return apply(command.op ?? .yank, to: range, linewise: true, cursor: cursor, document)
        case .textObject(let object, let around):
            guard let (range, linewise) = textObject(object, around: around, at: cursor, document) else {
                return [.beep]
            }
            if let op = command.op { return apply(op, to: range, linewise: linewise, cursor: cursor, document) }
            guard range.length > 0 else { return [.beep] }
            if linewise { mode = .visualLine }
            visualAnchor = range.location
            visualCursor = document.previous(NSMaxRange(range))
            return [.select(visualRange(document))]
        case .motion(let motion):
            if let op = command.op {
                // Pass the count as typed: `dG` (no count) and `d1G` go to different lines.
                return operate(op, motion: motion, count: command.count, cursor: cursor, document)
            }
            switch motion {
            case .down: return [.moveDisplayLines(count)]
            case .up: return [.moveDisplayLines(-count)]
            default: break
            }
            guard let target = target(of: motion, count: command.count, from: cursor, document) else { return [.beep] }
            if isVisual {
                if motion == .lineEnd {
                    // In visual mode `$` takes the line break too, so `v$d` joins the lines.
                    let end = document.contentEnd(target.position)
                    visualCursor = end < document.length ? end : max(document.length - 1, 0)
                } else {
                    visualCursor = min(target.position, max(document.length - 1, 0))
                }
                return [.select(visualRange(document))]
            }
            return [.select(NSRange(location: document.clampNormal(target.position), length: 0))]
        }
    }

    // MARK: Motions

    private struct Target {
        var position: Int
        var inclusive = false
        var linewise = false
    }

    private mutating func target(of motion: VimCommand.Motion, count: Int?, from cursor: Int, _ document: VimText)
        -> Target?
    {
        let times = count ?? 1
        func repeated(_ step: (Int) -> Int) -> Int {
            var position = cursor
            for _ in 0..<times { position = step(position) }
            return position
        }
        switch motion {
        case .left:
            return Target(position: max(document.lineStart(cursor), repeated(document.previous)))
        case .right:
            return Target(position: min(repeated(document.next), document.contentEnd(cursor)))
        case .down, .up:
            let line = document.lineIndex(cursor) + (motion == .down ? times : -times)
            guard line >= 0, line < document.lineCount else { return nil }
            return Target(position: document.firstNonBlank(document.lineStart(forLine: line)), linewise: true)
        case .wordForward(let big): return Target(position: repeated { document.wordForward(from: $0, big: big) })
        case .wordBackward(let big): return Target(position: repeated { document.wordBackward(from: $0, big: big) })
        case .wordEnd(let big):
            return Target(position: repeated { document.wordEnd(from: $0, big: big) }, inclusive: true)
        case .lineStart: return Target(position: document.lineStart(cursor))
        case .firstNonBlank: return Target(position: document.firstNonBlank(cursor))
        case .lineEnd:
            let line = document.lineStart(forLine: document.lineIndex(cursor) + times - 1)
            let end = document.contentEnd(line)
            return Target(position: end > line ? document.previous(end) : line, inclusive: true)
        case .documentStart, .documentEnd:
            let line = count.map { $0 - 1 } ?? (motion == .documentStart ? 0 : document.lineCount - 1)
            let start = document.lineStart(forLine: min(max(line, 0), document.lineCount - 1))
            return Target(position: document.firstNonBlank(start), linewise: true)
        case .find(let char, let forward, let till):
            lastFind = (char, forward, till)
            return findTarget(char, forward: forward, till: till, times: times, from: cursor, document)
        case .repeatFind(let reversed):
            guard let find = lastFind else { return nil }
            let forward = reversed ? !find.forward : find.forward
            // Repeating `t` skips the character it stopped in front of, without leaving the line.
            var start = cursor
            if find.till, forward, document.next(cursor) < document.contentEnd(cursor) { start = document.next(cursor) }
            if find.till, !forward, cursor > document.lineStart(cursor) { start = document.previous(cursor) }
            return findTarget(find.target, forward: forward, till: find.till, times: times, from: start, document)
        case .paragraphForward: return Target(position: document.paragraphForward(from: cursor, count: times))
        case .paragraphBackward: return Target(position: document.paragraphBackward(from: cursor, count: times))
        case .nextLine, .previousLine:
            let line = document.lineIndex(cursor) + (motion == .nextLine ? times : -times)
            guard line >= 0, line < document.lineCount else { return nil }
            return Target(position: document.firstNonBlank(document.lineStart(forLine: line)), linewise: true)
        case .searchNext(let reversed):
            guard let search = lastSearch else { return nil }
            let forward = reversed ? !search.forward : search.forward
            var position = cursor
            for _ in 0..<times {
                guard
                    let match = document.search(
                        search.pattern, from: position, forward: forward, wholeWord: search.wholeWord)
                else {
                    message = "Pattern not found: \(search.pattern)"
                    return nil
                }
                position = match
            }
            return Target(position: position)
        }
    }

    private func findTarget(
        _ char: Character, forward: Bool, till: Bool, times: Int, from cursor: Int, _ document: VimText
    ) -> Target? {
        document.find(char, from: cursor, forward: forward, till: till, count: times)
            .map { Target(position: $0, inclusive: forward) }
    }

    // MARK: Operators

    private mutating func operate(
        _ op: VimCommand.Operator, motion: VimCommand.Motion, count typedCount: Int?, cursor: Int, _ document: VimText
    ) -> [VimAction] {
        let count = typedCount ?? 1
        // `cw` on a word changes to the end of that word (not into the next one), then `count - 1` more words.
        if op == .change, case .wordForward(let big) = motion, document.characterClass(at: cursor, big: big) != 0 {
            var end = cursor
            let kind = document.characterClass(at: cursor, big: big)
            while document.next(end) < document.length,
                document.characterClass(at: document.next(end), big: big) == kind
            {
                end = document.next(end)
            }
            for _ in 1..<max(count, 1) { end = document.wordEnd(from: end, big: big) }
            return operateOnCharacters(op, from: cursor, to: Target(position: end, inclusive: true), document)
        }
        // `w` with an operator follows Vim's own rules (see `wordForwardForOperator`).
        if case .wordForward(let big) = motion {
            guard let end = document.wordForwardForOperator(from: cursor, count: count, big: big) else {
                guard op == .change else { return [.beep] }
                mode = .insert  // `cw` with nowhere to go still starts typing
                return [.select(NSRange(location: cursor, length: 0))]
            }
            return operateOnCharacters(op, from: cursor, to: Target(position: end), document)
        }
        // Operators work on logical lines; `j`/`k` alone move by display lines instead.
        guard var target = target(of: motion, count: typedCount, from: cursor, document) else { return [.beep] }
        if case .right = motion { target.position = min(target.position, document.contentEnd(cursor)) }
        if target.linewise {
            let lower = min(cursor, target.position)
            let upper = max(cursor, target.position)
            return apply(
                op, to: NSRange(document.lineStart(lower)..<document.lineEnd(upper)), linewise: true,
                cursor: cursor, document)
        }
        return operateOnCharacters(op, from: cursor, to: target, document)
    }

    private mutating func operateOnCharacters(
        _ op: VimCommand.Operator, from cursor: Int, to target: Target, _ document: VimText
    ) -> [VimAction] {
        let lower = min(cursor, target.position)
        let upper = max(cursor, target.position)
        var end =
            target.inclusive && upper < document.length && !document.isNewline(upper) ? document.next(upper) : upper
        // The final line break belongs to the last line; only linewise commands remove it.
        if end == document.length, document.endsWithLineBreak, end > lower { end -= 1 }
        // Vim's rule for exclusive motions that end in column 1 (`db` from a line start, `d}`): the line break
        // before the end stays, and if the motion started at or before the first non-blank it covers whole lines.
        if !target.inclusive, end > lower, document.isLineStart(end), document.lineStart(lower) != end {
            if lower <= document.firstNonBlank(lower) {
                return apply(
                    op, to: NSRange(document.lineStart(lower)..<end), linewise: true, cursor: cursor, document)
            }
            end -= 1
        }
        guard end > lower else {
            // `c` over nothing (`cw` on an empty line) still starts typing there.
            guard op == .change else { return [.beep] }
            mode = .insert
            return [.select(NSRange(location: lower, length: 0))]
        }
        // Vim's exception for `d`: across lines, with only blanks before the start and nothing but blanks after
        // the end, the delete takes whole lines instead of leaving an empty one behind.
        let lastIncluded = target.inclusive ? upper : max(end - 1, lower)
        if op == .delete, document.lineStart(lower) != document.lineStart(lastIncluded),
            lower <= document.firstNonBlank(lower),
            document.substring(min(end, document.contentEnd(lastIncluded))..<document.contentEnd(lastIncluded))
                .allSatisfy({ $0 == " " || $0 == "\t" })
        {
            return apply(
                op, to: NSRange(document.lineStart(lower)..<document.lineEnd(lastIncluded)), linewise: true,
                cursor: cursor, document)
        }
        return apply(op, to: NSRange(lower..<end), linewise: false, cursor: cursor, document)
    }

    /// The start of the last line covered by a counted line command (`3dd`), or nil when the count needs
    /// lines below the last one.
    private func lastLine(from cursor: Int, count: Int, _ document: VimText) -> Int? {
        let line = document.lineIndex(cursor)
        guard count <= 1 || line < document.lineCount - 1 else { return nil }
        return document.lineStart(forLine: min(line + count - 1, document.lineCount - 1))
    }

    private mutating func apply(
        _ op: VimCommand.Operator, to range: NSRange, linewise: Bool, cursor: Int, _ document: VimText
    ) -> [VimAction] {
        var range = range
        store(document.text.substring(with: range), linewise: linewise)
        switch op {
        case .yank:
            mode = .normal
            let position = linewise && document.lineStart(cursor) == range.location ? cursor : range.location
            return [.select(NSRange(location: document.clampNormal(position), length: 0))]
        case .delete:
            mode = .normal
            var cursorLine = range.location
            // Deleting the last lines also removes the line break before them.
            if linewise, NSMaxRange(range) == document.length, range.location > 0,
                !document.isNewline(document.length - 1)
            {
                range = NSRange(location: range.location - 1, length: range.length + 1)
                cursorLine = document.lineStart(range.location)
            }
            let result = VimText(document.text.replacingCharacters(in: range, with: "") as NSString)
            var position = min(range.location, result.length)
            if linewise {
                let line =
                    min(cursorLine, result.length) == result.length && result.endsWithLineBreak
                    ? result.lastLineStart : min(cursorLine, result.length)
                position = result.firstNonBlank(line)
            }
            return [.replace(range, with: ""), .select(NSRange(location: result.clampNormal(position), length: 0))]
        case .change:
            mode = .insert
            if linewise {
                let indent = document.indentation(range.location)
                // Keep the last line break so a line remains to type on.
                var content = range
                if content.length > 0, document.isNewline(NSMaxRange(content) - 1) { content.length -= 1 }
                return [
                    .replace(content, with: indent),
                    .select(NSRange(location: content.location + (indent as NSString).length, length: 0)),
                ]
            }
            return [.replace(range, with: ""), .select(NSRange(location: range.location, length: 0))]
        }
    }

    private mutating func store(_ text: String, linewise: Bool) {
        register = Register(text: linewise && !text.hasSuffix("\n") ? text + "\n" : text, linewise: linewise)
    }

    private mutating func textObject(
        _ object: VimCommand.TextObject, around: Bool, at cursor: Int, _ document: VimText
    ) -> (NSRange, Bool)? {
        switch object {
        case .word(let big): return document.wordObject(at: cursor, around: around, big: big).map { ($0, false) }
        case .quote(let quote): return document.quoteObject(quote, at: cursor, around: around).map { ($0, false) }
        case .bracket(let open, let close):
            return document.bracketObject(open: open, close: close, at: cursor, around: around).map { ($0, false) }
        case .paragraph: return document.paragraphObject(at: cursor, around: around).map { ($0, true) }
        }
    }

    // MARK: Simple commands

    private mutating func simpleCommand(
        _ simple: VimCommand.Simple, _ command: VimCommand, _ cursor: Int, _ document: VimText
    ) -> [VimAction] {
        let count = command.count ?? 1
        let lineStart = document.lineStart(cursor)
        let contentEnd = document.contentEnd(cursor)
        func insert(at position: Int) -> [VimAction] {
            mode = .insert
            return [.select(NSRange(location: position, length: 0))]
        }
        func charactersForward(_ times: Int) -> Int {
            var position = cursor
            for _ in 0..<times where position < contentEnd { position = document.next(position) }
            return position
        }

        switch simple {
        case .deleteChar:
            guard cursor < contentEnd else { return [.beep] }
            return apply(
                .delete, to: NSRange(cursor..<charactersForward(count)), linewise: false, cursor: cursor, document)
        case .deleteCharBefore:
            guard cursor > lineStart else { return [.beep] }
            var start = cursor
            for _ in 0..<count where start > lineStart { start = document.previous(start) }
            return apply(.delete, to: NSRange(start..<cursor), linewise: false, cursor: cursor, document)
        case .deleteToEnd, .changeToEnd:
            let op: VimCommand.Operator = simple == .deleteToEnd ? .delete : .change
            guard cursor < contentEnd || op == .change else { return [.beep] }
            return apply(op, to: NSRange(cursor..<contentEnd), linewise: false, cursor: cursor, document)
        case .yankLine, .substituteLine:
            guard let last = lastLine(from: cursor, count: count, document) else { return [.beep] }
            let range = NSRange(lineStart..<document.lineEnd(last))
            return apply(simple == .yankLine ? .yank : .change, to: range, linewise: true, cursor: cursor, document)
        case .substituteChar:
            return apply(
                .change, to: NSRange(cursor..<charactersForward(count)), linewise: false, cursor: cursor, document)
        case .putAfter, .putBefore:
            return put(after: simple == .putAfter, count: count, cursor: cursor, document)
        case .openBelow, .openAbove:
            let indent = document.indentation(cursor)
            let indentLength = (indent as NSString).length
            mode = .insert
            if simple == .openBelow {
                return [
                    .replace(NSRange(location: contentEnd, length: 0), with: "\n" + indent),
                    .select(NSRange(location: contentEnd + 1 + indentLength, length: 0)),
                ]
            }
            return [
                .replace(NSRange(location: lineStart, length: 0), with: indent + "\n"),
                .select(NSRange(location: lineStart + indentLength, length: 0)),
            ]
        case .insert: return insert(at: cursor)
        case .append: return insert(at: cursor < contentEnd ? document.next(cursor) : cursor)
        case .insertAtLineStart: return insert(at: document.firstNonBlank(cursor))
        case .appendAtLineEnd: return insert(at: contentEnd)
        case .joinLines:
            return join(from: cursor, lines: max(count, 2), document)
        case .replaceChar(let char):
            let end = charactersForward(count)
            var replaced = 0
            var position = cursor
            while position < end {
                replaced += 1
                position = document.next(position)
            }
            guard replaced == count else { return [.beep] }
            let replacement = String(repeating: String(char), count: count)
            let last = cursor + (replacement as NSString).length - (String(char) as NSString).length
            return [.replace(NSRange(cursor..<end), with: replacement), .select(NSRange(location: last, length: 0))]
        case .toggleCase:
            guard cursor < contentEnd else { return [.beep] }
            let end = charactersForward(count)
            let range = NSRange(cursor..<end)
            let toggled = String(document.text.substring(with: range).map(Self.toggledCase).joined())
            let result = VimText(document.text.replacingCharacters(in: range, with: toggled) as NSString)
            return [.replace(range, with: toggled), .select(NSRange(location: result.clampNormal(end), length: 0))]
        case .undo: return Array(repeating: .undo, count: count)
        case .redo: return Array(repeating: .redo, count: count)
        case .repeatLastChange: return lastChange.isEmpty ? [.beep] : [.replay(lastChange)]
        case .visual, .visualLine:
            mode = simple == .visual ? .visual : .visualLine
            visualAnchor = cursor
            visualCursor = cursor
            return [.select(visualRange(document))]
        case .commandLine(let prompt):
            mode = .commandLine(prompt: prompt, text: "")
            return []
        case .searchWord(let forward):
            guard let word = document.word(at: cursor) else { return [.beep] }
            lastSearch = (word, forward, true)
            guard let target = target(of: .searchNext(reversed: false), count: count, from: cursor, document) else {
                return [.beep]
            }
            return [.select(NSRange(location: target.position, length: 0))]
        case .centerCursor: return [.centerCursor]
        case .halfPageDown: return [.scrollHalfPage(down: true)]
        case .halfPageUp: return [.scrollHalfPage(down: false)]
        case .escape: return []
        case .swapVisualEnds, .lowercase, .uppercase: return [.beep]
        }
    }

    private mutating func put(after: Bool, count: Int, cursor: Int, _ document: VimText) -> [VimAction] {
        guard !register.text.isEmpty else { return [.beep] }
        let text = String(repeating: register.text, count: count)
        let length = (text as NSString).length
        if register.linewise {
            if after, document.length == 0 {
                // An empty document still has one (empty) line; the pasted lines go below it.
                return [
                    .replace(NSRange(location: 0, length: 0), with: "\n" + text),
                    .select(NSRange(location: 1 + leadingBlanks(text), length: 0)),
                ]
            }
            if after {
                let lineEnd = document.lineEnd(cursor)
                if lineEnd == document.contentEnd(cursor) {
                    // The last line has no line break: add one before the pasted lines.
                    let pasted = "\n" + String(text.dropLast())
                    return [
                        .replace(NSRange(location: lineEnd, length: 0), with: pasted),
                        .select(NSRange(location: lineEnd + 1 + leadingBlanks(text), length: 0)),
                    ]
                }
                return [
                    .replace(NSRange(location: lineEnd, length: 0), with: text),
                    .select(NSRange(location: lineEnd + leadingBlanks(text), length: 0)),
                ]
            }
            let start = document.lineStart(cursor)
            return [
                .replace(NSRange(location: start, length: 0), with: text),
                .select(NSRange(location: start + leadingBlanks(text), length: 0)),
            ]
        }
        let position = after && cursor < document.contentEnd(cursor) ? document.next(cursor) : cursor
        let result = VimText(
            document.text.replacingCharacters(in: NSRange(location: position, length: 0), with: text) as NSString)
        // Like Vim: after pasting several lines of text the cursor is at their start, otherwise on the last
        // pasted character.
        let caret = text.contains("\n") ? position : result.previous(position + length)
        return [
            .replace(NSRange(location: position, length: 0), with: text),
            .select(NSRange(location: caret, length: 0)),
        ]
    }

    private func leadingBlanks(_ text: String) -> Int {
        (String(text.prefix { $0 == " " || $0 == "\t" }) as NSString).length
    }

    private mutating func join(from cursor: Int, lines: Int, _ document: VimText) -> [VimAction] {
        let line = document.lineIndex(cursor)
        let available = document.lineCount - 1 - line
        guard available > 0 else { return [.beep] }
        let start = document.lineStart(cursor)
        var joined = document.substring(start..<document.contentEnd(cursor))
        var end = document.contentEnd(cursor)
        var joinPoint = (joined as NSString).length
        for offset in 1...min(max(lines - 1, 1), available) {
            let nextLine = document.lineStart(forLine: line + offset)
            let content = document.substring(document.firstNonBlank(nextLine)..<document.contentEnd(nextLine))
            joinPoint = (joined as NSString).length
            if content.isEmpty {
                // Joining an empty line adds nothing.
            } else if joined.hasSuffix(" ") || joined.isEmpty {
                joined += content
            } else {
                joined += " " + content
            }
            end = document.contentEnd(nextLine)
        }
        // The cursor goes where the lines were joined, staying on a character when nothing was appended.
        let result = VimText(document.text.replacingCharacters(in: NSRange(start..<end), with: joined) as NSString)
        return [
            .replace(NSRange(start..<end), with: joined),
            .select(NSRange(location: result.clampNormal(start + joinPoint), length: 0)),
        ]
    }

    // MARK: Visual mode

    private func visualRange(_ document: VimText) -> NSRange {
        let lower = min(visualAnchor, visualCursor)
        let upper = max(visualAnchor, visualCursor)
        if mode == .visualLine {
            return NSRange(document.lineStart(lower)..<document.lineEnd(upper))
        }
        let end = upper < document.length ? max(document.next(upper), lower) : document.length
        return NSRange(lower..<end)
    }

    private mutating func visualCommand(_ simple: VimCommand.Simple, count: Int, _ document: VimText) -> [VimAction] {
        var range = visualRange(document)
        let linewise = mode == .visualLine
        // A character selection can't take the document's final line break (it belongs to the last line).
        if !linewise, NSMaxRange(range) == document.length, document.endsWithLineBreak, range.length > 0 {
            range.length -= 1
        }
        let start = min(visualAnchor, visualCursor)
        switch simple {
        case .escape:
            mode = .normal
            return [.select(NSRange(location: document.clampNormal(visualCursor), length: 0))]
        case .visual, .visualLine:
            let target: VimMode = simple == .visual ? .visual : .visualLine
            if mode == target {
                mode = .normal
                return [.select(NSRange(location: document.clampNormal(visualCursor), length: 0))]
            }
            mode = target
            return [.select(visualRange(document))]
        case .swapVisualEnds:
            swap(&visualAnchor, &visualCursor)
            return [.select(range)]
        case .deleteChar:
            guard range.length > 0 || linewise else { return [.beep] }
            return apply(.delete, to: range, linewise: linewise, cursor: start, document)
        case .substituteChar:
            guard range.length > 0 || linewise else { return [.beep] }
            return apply(.change, to: range, linewise: linewise, cursor: start, document)
        case .yankLine:
            guard range.length > 0 || linewise else { return [.beep] }
            return apply(.yank, to: range, linewise: linewise, cursor: start, document)
        case .putAfter:
            guard !register.text.isEmpty else { return [.beep] }
            var text = register.text
            if register.linewise, !linewise { text = String(text.dropLast()) }
            store(document.text.substring(with: range), linewise: linewise)
            mode = .normal
            let end = range.location + (text as NSString).length
            return [.replace(range, with: text), .select(NSRange(location: max(range.location, end - 1), length: 0))]
        case .toggleCase, .lowercase, .uppercase:
            let original = document.text.substring(with: range)
            let changed =
                switch simple {
                case .lowercase: original.lowercased()
                case .uppercase: original.uppercased()
                default: original.map(Self.toggledCase).joined()
                }
            mode = .normal
            return [.replace(range, with: changed), .select(NSRange(location: range.location, length: 0))]
        case .joinLines:
            mode = .normal
            let lines = document.lineIndex(NSMaxRange(range) - 1) - document.lineIndex(range.location) + 1
            return join(from: range.location, lines: max(lines, 2), document)
        default:
            return [.beep]
        }
    }

    // MARK: Helpers

    private static func toggledCase(_ character: Character) -> String {
        let string = String(character)
        return character.isUppercase ? string.lowercased() : string.uppercased()
    }

    private static func describe(_ key: VimKey) -> String {
        switch key {
        case .char(let char): String(char)
        case .ctrl(let char): "^" + String(char).uppercased()
        default: ""
        }
    }
}

extension VimCommand {
    /// Commands the `.` command can repeat.
    var isChange: Bool {
        if let op { return op != .yank }
        guard case .simple(let simple) = action else { return false }
        switch simple {
        case .deleteChar, .deleteCharBefore, .deleteToEnd, .changeToEnd, .substituteChar, .substituteLine,
            .putAfter, .putBefore, .openBelow, .openAbove, .insert, .append, .insertAtLineStart,
            .appendAtLineEnd, .joinLines, .replaceChar, .toggleCase:
            return true
        default:
            return false
        }
    }
}
