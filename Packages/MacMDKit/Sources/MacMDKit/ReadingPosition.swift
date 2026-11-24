import Foundation

/// Where a reader stopped in a document, stored so reopening the file can offer to continue from there.
public struct ReadingPosition: Codable, Equatable, Sendable {
    /// 1-based source line at the top of the window.
    public var line: Int
    /// Slug of the heading at or above `line`, if any. Survives edits made above it.
    public var headingSlug: String?
    /// Lines between that heading and `line`.
    public var linesBelowHeading: Int
    public var readMode: Bool
    public var savedAt: Date

    public init(line: Int, headingSlug: String?, linesBelowHeading: Int, readMode: Bool, savedAt: Date = Date()) {
        self.line = line
        self.headingSlug = headingSlug
        self.linesBelowHeading = linesBelowHeading
        self.readMode = readMode
        self.savedAt = savedAt
    }

    /// A position near the top is not worth offering to resume.
    public static let trivialLine = 3

    /// Captures a position for `line` in a document with the given outline.
    public static func make(line: Int, outline: [OutlineItem], readMode: Bool, savedAt: Date = Date())
        -> ReadingPosition
    {
        let heading = outline.last { $0.line <= line }
        return ReadingPosition(
            line: line, headingSlug: heading?.slug, linesBelowHeading: heading.map { line - $0.line } ?? 0,
            readMode: readMode, savedAt: savedAt)
    }

    /// Where to resume in `text`, which may have changed since the position was saved.
    public struct Target: Equatable, Sendable {
        public let line: Int
        /// Title of the heading the target sits under, for the banner text.
        public let headingTitle: String?
        public let readMode: Bool
    }

    /// Re-anchors on the heading when it still exists, otherwise clamps the saved line to the text.
    /// Returns nil when there is nothing worth resuming.
    public func resolve(in text: String) -> Target? {
        let lineCount = TextMetrics.lineNumber(in: text, atUTF16Offset: .max)
        let outline = Outline.items(for: text)
        var target = min(max(line, 1), lineCount)
        var title: String?
        if let slug = headingSlug, let index = outline.firstIndex(where: { $0.slug == slug }) {
            let heading = outline[index]
            let next = outline.dropFirst(index + 1).first?.line ?? (lineCount + 1)
            target = min(heading.line + linesBelowHeading, max(next - 1, heading.line))
            title = heading.title
        } else {
            title = outline.last { $0.line <= target }?.title
        }
        target = min(max(target, 1), lineCount)
        guard target > Self.trivialLine else { return nil }
        return Target(line: target, headingTitle: title, readMode: readMode)
    }
}

/// A bounded, most-recently-saved-first collection of reading positions keyed by file path.
public struct ReadingPositionStore: Codable, Equatable, Sendable {
    public static let capacity = 200

    private var entries: [String: ReadingPosition]

    public init(entries: [String: ReadingPosition] = [:]) {
        self.entries = entries
    }

    public var count: Int { entries.count }

    public func position(for key: String) -> ReadingPosition? { entries[key] }

    public mutating func record(_ position: ReadingPosition, for key: String) {
        entries[key] = position
        guard entries.count > Self.capacity else { return }
        let overflow = entries.count - Self.capacity
        let oldest = entries.sorted { $0.value.savedAt < $1.value.savedAt }.prefix(overflow)
        for (key, _) in oldest { entries[key] = nil }
    }

    public mutating func remove(_ key: String) { entries[key] = nil }
}
