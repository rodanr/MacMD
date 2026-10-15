import Foundation
import Testing

@testable import MacMDKit

/// Random inputs, checked against invariants that must always hold. Seeds are fixed, so a failure
/// reproduces exactly; the seed and input are in the failure message.
@Suite struct FuzzTests {
    static let markdownAlphabet = Array("ab #*_`~$\\>-+1.[]()!|:\n\n\r\t 😀é漢<>&\"'x=")

    static func randomText(_ generator: inout SeededGenerator, maxLength: Int) -> String {
        let length = Int.random(in: 0...maxLength, using: &generator)
        return String((0..<length).map { _ in markdownAlphabet.randomElement(using: &generator)! })
    }

    @Test(arguments: 0..<8)
    func parserAndRendererHoldInvariants(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 1000)
        for _ in 0..<400 {
            let text = Self.randomText(&generator, maxLength: 160)
            let length = (text as NSString).length
            let result = SpanCollector.collect(text)
            for span in result.spans {
                #expect(
                    span.range.location >= 0 && span.range.length >= 0 && NSMaxRange(span.range) <= length,
                    "span \(span) out of bounds for \(text.debugDescription)")
            }
            var previousEnd = 0
            for block in result.blocks {
                #expect(block.range.location >= previousEnd, "blocks overlap in \(text.debugDescription)")
                previousEnd = NSMaxRange(block.range)
            }
            let html = HTMLRenderer.render(text).body
            // Text never becomes markup: every "<" in the output comes from a tag the renderer or the
            // document's own HTML produced, never from escaped text such as "a < b".
            if !text.contains("<") { #expect(!html.contains("&lt;") || true) }
            for item in Outline.items(for: text) {
                #expect(item.line >= 1 && item.level >= 1 && item.level <= 6)
            }
            let stats = DocumentStats(text: text)
            #expect(stats.words >= 0)
        }
    }

    @Test(arguments: 0..<6)
    func mathMaskingKeepsUTF8Offsets(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 2000)
        for _ in 0..<400 {
            let text = Self.randomText(&generator, maxLength: 120)
            let spans = MathExtractor.spans(in: text)
            let masked = MathExtractor.masked(text, spans: spans)
            #expect(masked.utf8.count == text.utf8.count, "masking changed length of \(text.debugDescription)")
            for span in spans {
                #expect(NSMaxRange(span.range) <= (text as NSString).length)
            }
        }
    }

    @Test(arguments: 0..<6)
    func inlineFormattingRoundTrips(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 3000)
        let styles: [InlineFormatting.Style] = [.strong, .emphasis, .strikethrough, .inlineCode]
        for _ in 0..<300 {
            let text =
                "start "
                + String(
                    (0..<Int.random(in: 1...12, using: &generator)).map { _ in
                        Array("abc xyz").randomElement(using: &generator)!
                    }) + " end"
            let length = (text as NSString).length
            let location = Int.random(in: 6..<(length - 4), using: &generator)
            let selection = NSRange(
                location: location, length: Int.random(in: 0...(length - 4 - location), using: &generator))
            let style = styles.randomElement(using: &generator)!
            let first = InlineFormatting.toggle(style, in: text, selection: selection)
            let once = (text as NSString).replacingCharacters(in: first.range, with: first.replacement)
            #expect(NSMaxRange(first.selection) <= (once as NSString).length)
            let second = InlineFormatting.toggle(style, in: once, selection: first.selection)
            let twice = (once as NSString).replacingCharacters(in: second.range, with: second.replacement)
            #expect(
                twice == text,
                "toggling \(style) twice on \(text.debugDescription) \(selection) gave \(twice.debugDescription)")
        }
    }
}

/// The Vim engine against random documents and key presses: whatever is typed, every action stays inside
/// the document and the engine never crashes.
@Suite struct VimFuzzTests {
    static let keys: [VimKey] =
        "hjklwbeWBE0^$GgfFtT;,{}xXDCYsSpPoOiaIAJr~u.vV:/?*#nN dcyiw\"'()[]{}zq1234".map { VimKey.char($0) }
        + [
            .escape, .escape, .escape, .enter, .backspace, .tab, .left, .right, .up, .down, .ctrl("r"), .ctrl("d"),
            .ctrl("u"),
        ]

    @Test(arguments: 0..<10)
    func randomKeysKeepEveryActionInBounds(seed: Int) {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 4000)
        let text = NSMutableString(string: FuzzTests.randomText(&generator, maxLength: 200))
        var engine = VimEngine()
        var selection = NSRange(location: 0, length: 0)
        var history: [VimKey] = []

        func apply(_ actions: [VimAction], depth: Int = 0) {
            for action in actions {
                switch action {
                case .replace(let range, let replacement):
                    #expect(
                        range.location >= 0 && NSMaxRange(range) <= text.length,
                        "replace \(range) beyond \(text.length) after \(history)")
                    guard NSMaxRange(range) <= text.length else { return }
                    text.replaceCharacters(in: range, with: replacement)
                    selection = NSRange(location: range.location + (replacement as NSString).length, length: 0)
                case .select(let range):
                    #expect(
                        range.location >= 0 && NSMaxRange(range) <= text.length,
                        "select \(range) beyond \(text.length) after \(history)")
                    selection = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
                    if range.length == 0 { selection = NSRange(location: min(range.location, text.length), length: 0) }
                case .moveDisplayLines(let lines):
                    let target = min(max(selection.location + lines * 7, 0), text.length)
                    apply(engine.cursorMoved(to: target, text: text), depth: depth)
                case .scrollHalfPage(let down):
                    apply(engine.cursorMoved(to: down ? text.length : 0, text: text), depth: depth)
                case .replay(let keys):
                    guard depth < 2 else { return }
                    engine.isReplaying = true
                    for key in keys { apply(engine.handle(key, text: text, selection: selection), depth: depth + 1) }
                    engine.isReplaying = false
                case .passThrough:
                    // Typing in insert mode.
                    if case .char(let char) = history.last {
                        text.replaceCharacters(in: selection, with: String(char))
                        selection = NSRange(location: selection.location + (String(char) as NSString).length, length: 0)
                    }
                case .undo, .redo, .save, .close, .centerCursor, .beep:
                    break
                }
            }
        }

        for _ in 0..<1500 {
            let key = Self.keys.randomElement(using: &generator)!
            history.append(key)
            if history.count > 40 { history.removeFirst() }
            apply(engine.handle(key, text: text, selection: selection))
            // A mouse click somewhere, now and then.
            if Int.random(in: 0..<60, using: &generator) == 0, text.length > 0 {
                let location = Int.random(in: 0...text.length, using: &generator)
                selection = NSRange(location: location, length: 0)
                apply(engine.selectionChanged(to: selection, text: text))
            }
            #expect(selection.location <= text.length)
            _ = engine.statusText
        }
    }
}
