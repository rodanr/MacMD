import AppKit
import MacMDKit
import Testing

@testable import MacMD

/// The editor restyles only the blocks an edit touched. Whatever the edits, the result must look exactly
/// like styling the final text from scratch; otherwise stale styling (a line still bold after its `**`
/// was deleted) stays on screen.
@MainActor
@Suite struct StylingConsistencyTests {
    private static let initial = """
        # Title

        Some **bold** and *italic* text with `code` and $x^2$.

        - one
        - [ ] task
          - nested

        > quote
        > more

        ```swift
        let a = 1
        ```

        | a | b |
        |---|---|
        | 1 | 2 |

        Setext
        ------
        end
        """

    private static let fragments = [
        "**", "*", "`", "```\n", "# ", "## ", "\n", "\n\n", "- ", "1. ", "> ", "$", "$$\n", "---\n", "x", "word ",
        "[link](u)", "| c |", "~~", "<b>", "\\", "😀", "Title\n===\n",
    ]

    @Test(arguments: 0..<12)
    func incrementalStylingMatchesAFreshPass(seed: Int) async {
        var random = SplitMix(seed: UInt64(seed) &+ 77)
        let theme = Theme(id: .paper, fontSize: 16)
        let storage = NSTextStorage(string: Self.initial)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let engine = StyleEngine(storage: storage, textView: textView, theme: theme)
        await engine.settled()

        for step in 0..<80 {
            var edits: [String] = []
            for _ in 0..<Int.random(in: 1...3, using: &random) {
                let length = storage.length
                let location = Int.random(in: 0...length, using: &random)
                let deletion = Int.random(in: 0...min(6, length - location), using: &random)
                let insertion = Bool.random(using: &random) ? Self.fragments.randomElement(using: &random)! : ""
                let range = NSRange(location: location, length: deletion)
                // New text takes the style of the character before it, like typing does.
                let attributes = location > 0 ? storage.attributes(at: location - 1, effectiveRange: nil) : [:]
                storage.replaceCharacters(
                    in: range, with: NSAttributedString(string: insertion, attributes: attributes))
                edits.append("\(range) ← \(insertion.debugDescription)")
            }
            await engine.settled()

            let fresh = NSTextStorage(string: storage.string)
            let freshStyler = MarkdownStyler(theme: theme)
            freshStyler.apply(SpanCollector.collect(fresh.string), to: fresh, dirty: nil, full: true)
            if let difference = firstDifference(storage, fresh) {
                Issue.record(
                    "seed \(seed) step \(step) after \(edits): \(difference)\ntext: \(storage.string.debugDescription)")
                return
            }
        }
    }

    /// The first character whose attributes differ, described for the failure message.
    private func firstDifference(_ lhs: NSTextStorage, _ rhs: NSTextStorage) -> String? {
        guard lhs.string == rhs.string else { return "texts differ" }
        let text = lhs.string as NSString
        for index in 0..<lhs.length {
            let left = normalized(lhs.attributes(at: index, effectiveRange: nil))
            let right = normalized(rhs.attributes(at: index, effectiveRange: nil))
            if left != right {
                let line = text.lineRange(for: NSRange(location: index, length: 0))
                let keys = Set(left.keys).union(right.keys).filter { left[$0] != right[$0] }.sorted()
                let details = keys.map { "\($0): incremental=\(left[$0] ?? "nil") fresh=\(right[$0] ?? "nil")" }
                return "at \(index) in line \(text.substring(with: line).debugDescription): \(details)"
            }
        }
        return nil
    }

    private func normalized(_ attributes: [NSAttributedString.Key: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in attributes {
            switch value {
            case let font as NSFont:
                result[key.rawValue] = "\(font.fontName) \(font.pointSize)"
            case let color as NSColor:
                var resolved = ""
                NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                    let rgb = color.usingColorSpace(.sRGB)
                    resolved =
                        rgb.map {
                            String(
                                format: "%.3f %.3f %.3f %.3f", $0.redComponent, $0.greenComponent, $0.blueComponent,
                                $0.alphaComponent)
                        } ?? "\(color)"
                }
                result[key.rawValue] = resolved
            default:
                result[key.rawValue] = "\(value)"
            }
        }
        return result
    }
}

/// A deterministic generator, so a failing seed reproduces.
struct SplitMix: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
