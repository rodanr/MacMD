import Foundation

/// Cheap positional queries on text, in UTF-16 units.
public enum TextMetrics {
    /// 1-based line containing `offset`. `\r\n` and lone `\r` count as one line break each.
    public static func lineNumber(in text: String, atUTF16Offset offset: Int) -> Int {
        let units = text.utf16
        let end = min(max(offset, 0), units.count)
        var line = 1
        var previous: UInt16 = 0
        for unit in units.prefix(end) {
            if unit == 0x0A {
                if previous != 0x0D { line += 1 }
            } else if unit == 0x0D {
                line += 1
            }
            previous = unit
        }
        return line
    }
}
