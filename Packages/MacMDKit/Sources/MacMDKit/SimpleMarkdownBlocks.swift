import Foundation

/// Splits a small, simple Markdown document (headings, paragraphs, bullets) into blocks for native display,
/// such as the license and terms in the About window. Hard-wrapped lines are joined, the document title is
/// dropped, and links to relative paths keep only their text because they can't be followed from the app.
public enum SimpleMarkdownBlocks {
    public enum Block: Equatable, Sendable {
        case heading(String)
        case paragraph(String)
        case bullet(String)
    }

    public static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var current: Block?

        func flush() {
            if let block = current { blocks.append(block) }
            current = nil
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if trimmed.hasPrefix("# ") {
                flush()
            } else if trimmed.hasPrefix("#") {
                flush()
                blocks.append(.heading(String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flush()
                current = .bullet(String(trimmed.dropFirst(2)))
            } else {
                switch current {
                case .bullet(let text): current = .bullet(text + " " + trimmed)
                case .paragraph(let text): current = .paragraph(text + " " + trimmed)
                case .heading, nil:
                    flush()
                    current = .paragraph(trimmed)
                }
            }
        }
        flush()
        return blocks.map(unlinkingRelativeLinks)
    }

    private static func unlinkingRelativeLinks(_ block: Block) -> Block {
        func strip(_ text: String) -> String {
            text.replacing(/\[([^\]]+)\]\((?!https?:|mailto:)[^)]*\)/) { String($0.output.1) }
        }
        return switch block {
        case .heading(let text): .heading(strip(text))
        case .paragraph(let text): .paragraph(strip(text))
        case .bullet(let text): .bullet(strip(text))
        }
    }
}
