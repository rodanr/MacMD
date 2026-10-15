import Foundation
import Markdown

/// Shared entry point for parsing Markdown with the options MacMD relies on.
enum MarkdownParser {
    static func parse(_ text: String) -> Document {
        Document(parsing: text)
    }
}
