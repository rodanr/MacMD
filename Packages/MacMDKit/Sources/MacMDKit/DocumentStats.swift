import Foundation

/// Word, character and reading-time statistics for a document.
public struct DocumentStats: Hashable, Sendable {
    public static let wordsPerMinute = 230

    public let words: Int
    public let characters: Int

    public init(text: String) {
        var words = 0
        (text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (text as NSString).length),
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in words += 1 }
        self.words = words
        self.characters = text.count
    }

    public var readingMinutes: Int {
        (words + Self.wordsPerMinute - 1) / Self.wordsPerMinute
    }
}
