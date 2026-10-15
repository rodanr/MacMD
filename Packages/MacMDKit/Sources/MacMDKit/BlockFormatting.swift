/// Line-level Markdown transformations.
public enum BlockFormatting {
    /// Returns `line` as an ATX heading of `level` (1–6), or as plain text for level 0.
    public static func settingHeading(level: Int, line: String) -> String {
        var content = Substring(line).drop { $0 == " " }
        let hashes = content.prefix { $0 == "#" }
        let afterHashes = content.dropFirst(hashes.count)
        if (1...6).contains(hashes.count), afterHashes.isEmpty || afterHashes.first == " " {
            content = afterHashes.drop { $0 == " " }
        }
        guard level > 0 else { return String(content) }
        return String(repeating: "#", count: min(level, 6)) + " " + content
    }
}
