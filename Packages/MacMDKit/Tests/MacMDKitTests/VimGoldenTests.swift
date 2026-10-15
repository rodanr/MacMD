import Foundation
import Testing

@testable import MacMDKit

/// Differential test: single normal-mode commands on random documents, compared with what real Vim did
/// (recorded by `scripts/generate-vim-golden.py` into `Fixtures/vim-golden.json`).
@Suite struct VimGoldenTests {
    struct Case: Decodable {
        let text: String
        let line: Int
        let col: Int
        let keys: [String]
        let result: String
        let endLine: Int
        let endCol: Int
    }

    static func cases() throws -> [Case] {
        let url = try #require(
            Bundle.module.url(forResource: "vim-golden", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    @Test func engineMatchesRealVim() throws {
        var failures: [String: [String]] = [:]
        let cases = try Self.cases()
        for testCase in cases {
            let outcome = Self.run(testCase)
            let expectedCursor = Self.offset(line: testCase.endLine, col: testCase.endCol, in: testCase.result)
            if outcome.text != testCase.result || outcome.cursor != expectedCursor {
                let command = testCase.keys.joined()
                failures[command, default: []].append(
                    "\(testCase.text.debugDescription) at \(testCase.line):\(testCase.col) → "
                        + "vim \(testCase.result.debugDescription) @\(expectedCursor), "
                        + "engine \(outcome.text.debugDescription) @\(outcome.cursor)")
            }
        }
        let total = failures.values.map(\.count).reduce(0, +)
        let report = failures.sorted { $0.value.count > $1.value.count }.map { command, examples in
            "\(command) ×\(examples.count): \(examples[0])"
        }
        #expect(total == 0, "\(total) of \(cases.count) cases differ from Vim:\n\(report.joined(separator: "\n"))")
    }

    static func offset(line: Int, col: Int, in text: String) -> Int {
        let lines = text.components(separatedBy: "\n")
        let before = lines.prefix(line - 1).map { ($0 as NSString).length + 1 }.reduce(0, +)
        return before + col - 1
    }

    /// Runs the keys through the engine, applying its actions like the editor does.
    static func run(_ testCase: Case) -> (text: String, cursor: Int) {
        let text = NSMutableString(string: testCase.text)
        var selection = NSRange(location: offset(line: testCase.line, col: testCase.col, in: testCase.text), length: 0)
        var engine = VimEngine()

        func apply(_ actions: [VimAction], key: VimKey?) {
            for action in actions {
                switch action {
                case .passThrough:
                    if case .char(let char)? = key {
                        text.replaceCharacters(in: selection, with: String(char))
                        selection = NSRange(location: selection.location + 1, length: 0)
                    }
                case .replace(let range, let replacement):
                    text.replaceCharacters(in: range, with: replacement)
                    selection = NSRange(location: range.location + (replacement as NSString).length, length: 0)
                case .select(let range):
                    selection = range
                case .moveDisplayLines(let lines):
                    // Short lines never wrap, so display lines are logical lines; keep the column like Vim.
                    let document = text as NSString
                    let current = document.lineRange(for: NSRange(location: selection.location, length: 0))
                    let column = selection.location - current.location
                    var target = current.location
                    for _ in 0..<abs(lines) {
                        if lines > 0 {
                            let end = NSMaxRange(document.lineRange(for: NSRange(location: target, length: 0)))
                            if end < document.length { target = end }
                        } else if target > 0 {
                            target = document.lineRange(for: NSRange(location: target - 1, length: 0)).location
                        }
                    }
                    let line = document.lineRange(for: NSRange(location: target, length: 0))
                    apply(engine.cursorMoved(to: min(target + column, NSMaxRange(line) - 1), text: text), key: nil)
                case .replay(let keys):
                    engine.isReplaying = true
                    for replayed in keys {
                        apply(engine.handle(replayed, text: text, selection: selection), key: replayed)
                    }
                    engine.isReplaying = false
                default:
                    break
                }
            }
        }

        for token in testCase.keys {
            let key: VimKey = token == "<Esc>" ? .escape : .char(Character(token))
            apply(engine.handle(key, text: text, selection: selection), key: key)
        }
        if engine.mode != .normal { apply(engine.handle(.escape, text: text, selection: selection), key: .escape) }
        return (text as String, selection.location)
    }
}
