import Foundation

/// Helpers for the private-use math tokens produced by `MathExtractor.replacingWithPlaceholders`.
enum Placeholder {
    /// Replaces tokens in `text`, calling `transform` with each math span; strips line filler.
    static func replacing(in text: String, math: [Int: MathSpan], with transform: (MathSpan) -> String) -> String {
        guard !math.isEmpty else { return text }
        let replaced = text.replacing(/\x{E000}(\d+)[\n\x{E002}]*\x{E001}?/) { match in
            Int(match.output.1).flatMap { math[$0] }.map(transform) ?? ""
        }
        return replaced.filter { $0 != MathExtractor.lineFiller && $0 != MathExtractor.tokenEnd }
    }

    static func restoringTeX(in text: String, math: [Int: MathSpan]) -> String {
        replacing(in: text, math: math) { $0.tex }
    }

    /// The math span when `text` consists solely of one token (plus filler/whitespace).
    static func soleMath(in text: String, math: [Int: MathSpan]) -> MathSpan? {
        guard !math.isEmpty else { return nil }
        let stripped = text.filter {
            !$0.isWhitespace && $0 != MathExtractor.lineFiller && $0 != MathExtractor.tokenEnd
        }
        guard let match = stripped.wholeMatch(of: /\x{E000}(\d+)/) else { return nil }
        return Int(match.output.1).flatMap { math[$0] }
    }
}
