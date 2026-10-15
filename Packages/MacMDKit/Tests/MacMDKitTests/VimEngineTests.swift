import Foundation
import Testing

@testable import MacMDKit

/// Plays the editor's part: applies the engine's actions to a string. `|` marks the cursor
/// (in normal mode it sits on the character after the bar).
private struct Editor {
    var engine = VimEngine()
    let text: NSMutableString
    var selection: NSRange
    var actions: [VimAction] = []

    init(_ marked: String) {
        let bar = marked.range(of: "|")!
        selection = NSRange(location: (String(marked[..<bar.lowerBound]) as NSString).length, length: 0)
        text = NSMutableString(string: marked.replacingCharacters(in: bar, with: ""))
    }

    var marked: String {
        let result = NSMutableString(string: text)
        result.insert("|", at: selection.location)
        return result as String
    }

    mutating func type(_ keys: String) -> String {
        for key in Self.keys(keys) { apply(engine.handle(key, text: text, selection: selection), typed: key) }
        return marked
    }

    private mutating func apply(_ list: [VimAction], typed key: VimKey?) {
        for action in list {
            actions.append(action)
            switch action {
            case .passThrough:
                switch key {
                case .char(let char)?: replace(selection, with: String(char))
                case .enter?: replace(selection, with: "\n")
                case .backspace?:
                    replace(NSRange(location: selection.location - 1, length: 1), with: "")
                default: break
                }
            case .replace(let range, let replacement): replace(range, with: replacement)
            case .select(let range): selection = range
            case .moveDisplayLines(let lines):
                // Without layout, display lines are logical lines; keep the column.
                let document = text as NSString
                let line = document.lineRange(for: NSRange(location: selection.location, length: 0))
                let column = selection.location - line.location
                var target = line.location
                if lines > 0 {
                    for _ in 0..<lines
                    where NSMaxRange(document.lineRange(for: NSRange(location: target, length: 0))) < document.length {
                        target = NSMaxRange(document.lineRange(for: NSRange(location: target, length: 0)))
                    }
                } else {
                    for _ in 0..<(-lines) where target > 0 {
                        target = document.lineRange(for: NSRange(location: target - 1, length: 0)).location
                    }
                }
                let targetLine = document.lineRange(for: NSRange(location: target, length: 0))
                apply(engine.cursorMoved(to: min(target + column, NSMaxRange(targetLine)), text: text), typed: nil)
            case .replay(let keys):
                engine.isReplaying = true
                for key in keys { apply(engine.handle(key, text: text, selection: selection), typed: key) }
                engine.isReplaying = false
            default:
                break
            }
        }
    }

    private mutating func replace(_ range: NSRange, with replacement: String) {
        text.replaceCharacters(in: range, with: replacement)
        selection = NSRange(location: range.location + (replacement as NSString).length, length: 0)
    }

    static func keys(_ string: String) -> [VimKey] {
        var keys: [VimKey] = []
        var rest = Substring(string)
        let named: [String: VimKey] = [
            "<esc>": .escape, "<cr>": .enter, "<bs>": .backspace, "<c-r>": .ctrl("r"), "<c-d>": .ctrl("d"),
        ]
        while let first = rest.first {
            if let (name, key) = named.first(where: { rest.hasPrefix($0.key) }) {
                keys.append(key)
                rest = rest.dropFirst(name.count)
            } else {
                keys.append(.char(first))
                rest = rest.dropFirst()
            }
        }
        return keys
    }
}

private func vim(_ marked: String, _ keys: String) -> String {
    var editor = Editor(marked)
    return editor.type(keys)
}

struct VimMotionTests {
    @Test(arguments: [
        ("|one two three", "w", "one |two three"),
        ("|one two three", "2w", "one two |three"),
        ("one |two", "b", "|one two"),
        ("|one two", "e", "on|e two"),
        ("|foo.bar baz", "w", "foo|.bar baz"),
        ("|foo.bar baz", "W", "foo.bar |baz"),
        ("|a\n\nb", "w", "a\n|\nb"),
        ("a|bc", "$", "ab|c"),
        ("ab|c", "0", "|abc"),
        ("  a|b", "^", "  |ab"),
        ("|a,b,c", "f,;", "a,b|,c"),
        ("|a,b,c", "t,", "|a,b,c"),
        ("a,b,|c", "F,", "a,b|,c"),
        ("|a\nb\nc", "2j", "a\nb\n|c"),
        ("a\nb\n|c", "gg", "|a\nb\nc"),
        ("|a\nb\nc", "G", "a\nb\n|c"),
        ("|a\nb\nc", "2G", "a\n|b\nc"),
        ("|a\nb\n\nc", "}", "a\nb\n|\nc"),
        ("|abc", "l", "a|bc"),
        ("ab|c", "l", "ab|c"),
        ("|😀b", "l", "😀|b"),
    ])
    func motions(start: String, keys: String, expected: String) {
        #expect(vim(start, keys) == expected)
    }

    @Test func searchWrapsAround() {
        var editor = Editor("|foo bar foo")
        #expect(editor.type("/foo<cr>") == "foo bar |foo")
        #expect(editor.type("n") == "|foo bar foo")
        #expect(editor.type("N") == "foo bar |foo")
    }

    @Test func starSearchesWholeWords() {
        #expect(vim("|cat concat cat", "*") == "cat concat |cat")
    }

    @Test func colonNumberJumpsToLine() {
        #expect(vim("|a\nb\nc", ":3<cr>") == "a\nb\n|c")
    }
}

struct VimEditingTests {
    @Test(arguments: [
        ("a|bc", "x", "a|c"),
        ("a|bc", "X", "|bc"),
        ("|😀b", "x", "|b"),
        ("|one two three", "dw", "|two three"),
        ("one |two\nthree", "dw", "one| \nthree"),
        ("|one two", "cwxyz<esc>", "xy|z two"),
        ("a\n|b\nc", "dd", "a\n|c"),
        ("a\n|b", "dd", "|a"),
        ("|a\nb\nc", "2dd", "|c"),
        ("|a\nb\nc", "dj", "|c"),
        ("|a\nb", "yyp", "a\n|a\nb"),
        ("a\n|b", "yyP", "a\n|b\nb"),
        ("|ab", "xp", "b|a"),
        ("foo |bar baz", "ciwX<esc>", "foo |X baz"),
        ("say \"he|llo\" now", "di\"", "say \"|\" now"),
        ("f(a, |b) x", "da(", "f| x"),
        ("|abc,d", "dt,", "|,d"),
        ("a|bc", "D", "|a"),
        ("|abc", "rx", "|xbc"),
        ("|ab", "~~", "A|B"),
        ("|a\n  b", "J", "a| b"),
        ("|a\nb", "ox<esc>", "a\n|x\nb"),
        ("a\n|b", "Ox<esc>", "a\n|x\nb"),
        ("  |a", "ccb<esc>", "  |b"),
        ("|ab", "Ac<esc>", "ab|c"),
        ("|ab", "Ic<esc>", "|cab"),
        ("|a\nb\n\nc", "dap", "|c"),
        ("|a b c", "x.", "|b c"),
        ("|ab", "ix<esc>.", "|xxab"),
        ("|one two three", "dw.", "|three"),
    ])
    func edits(start: String, keys: String, expected: String) {
        #expect(vim(start, keys) == expected)
    }

    @Test func undoAndRedoAreDelegatedToTheEditor() {
        var editor = Editor("|abc")
        _ = editor.type("2u<c-r>")
        #expect(editor.actions == [.undo, .undo, .redo])
    }

    @Test func exCommands() {
        var editor = Editor("|abc")
        _ = editor.type(":wq<cr>")
        #expect(editor.actions == [.save, .close])
        var unknown = Editor("|abc")
        _ = unknown.type(":nope<cr>")
        #expect(unknown.engine.statusText == "Unknown command: nope")
    }
}

struct VimModeTests {
    @Test func visualDeleteAndYank() {
        #expect(vim("|hello world", "vex") == "| world")
        #expect(vim("a\n|b\nc", "Vd") == "a\n|c")
        #expect(vim("|hello world", "veyP") == "hell|ohello world")
    }

    @Test func visualTextObjectAndCase() {
        #expect(vim("x |foo y", "viwU") == "x |FOO y")
        #expect(vim("|ab", "v$~") == "|AB")
    }

    @Test func statusShowsModeAndPendingKeys() {
        var editor = Editor("|abc")
        #expect(editor.engine.statusText == "NORMAL")
        _ = editor.type("2d")
        #expect(editor.engine.statusText == "NORMAL  2d")
        _ = editor.type("<esc>i")
        #expect(editor.engine.statusText == "INSERT")
        _ = editor.type("<esc>v")
        #expect(editor.engine.statusText == "VISUAL")
        _ = editor.type("<esc>:w")
        #expect(editor.engine.statusText == ":w")
    }

    @Test func mouseSelectionEntersVisualMode() {
        var engine = VimEngine()
        let text: NSString = "hello"
        _ = engine.selectionChanged(to: NSRange(location: 1, length: 3), text: text)
        #expect(engine.mode == .visual)
        #expect(engine.selectionChanged(to: NSRange(location: 2, length: 0), text: text) == [])
        #expect(engine.mode == .normal)
    }

    @Test func normalModeCursorNeverRestsOnALineBreak() {
        var engine = VimEngine()
        let actions = engine.selectionChanged(to: NSRange(location: 3, length: 0), text: "abc\nd")
        #expect(actions == [.select(NSRange(location: 2, length: 0))])
    }

    @Test func escapeLeavesInsertModeOneCharacterLeft() {
        #expect(vim("ab|c", "i<esc>") == "a|bc")
        #expect(vim("|abc", "i<esc>") == "|abc")
    }
}
