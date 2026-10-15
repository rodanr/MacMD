/// What pressing Return at the end of a line should do to keep a list or quote going.
public enum ListContinuation: Hashable, Sendable {
    /// Insert a newline followed by `prefix`.
    case `continue`(prefix: String)
    /// The item is empty: remove its marker (the first `markerLength` UTF-16 units of the line).
    case terminate(markerLength: Int)
    case notAList

    public static let indentUnit = "    "

    public static func forLine(_ line: String) -> ListContinuation {
        if let match = line.prefixMatch(of: /^(\s*(?:>\s?)*)(?:([-+*])|(\d{1,9})([.)]))(\s+)(\[[ xX]\]\s)?/) {
            let (whole, leading, bullet, number, delimiter, spacing, checkbox) = match.output
            if line.count == whole.count { return .terminate(markerLength: whole.utf16.count) }
            let marker: String
            if let bullet {
                marker = String(bullet)
            } else if let number, let delimiter, let value = Int(number) {
                marker = "\(value + 1)\(delimiter)"
            } else {
                return .notAList
            }
            return .continue(prefix: "\(leading)\(marker)\(spacing)\(checkbox == nil ? "" : "[ ] ")")
        }
        if let match = line.prefixMatch(of: /^(\s*(?:>\s?)+)/) {
            let prefix = String(match.output.1)
            if line.count == prefix.count { return .terminate(markerLength: prefix.utf16.count) }
            return .continue(prefix: prefix.hasSuffix(" ") ? prefix : prefix + " ")
        }
        return .notAList
    }

    public static func indented(_ line: String) -> String { indentUnit + line }

    public static func outdented(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        let spaces = line.prefix { $0 == " " }.count
        return String(line.dropFirst(min(spaces, indentUnit.count)))
    }
}
