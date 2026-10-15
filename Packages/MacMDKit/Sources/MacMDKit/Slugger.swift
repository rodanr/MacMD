/// Generates GitHub-compatible heading anchors, de-duplicating repeats (`intro`, `intro-1`, …).
public struct Slugger: Sendable {
    private var seen: [String: Int] = [:]

    public init() {}

    public mutating func slug(_ title: String) -> String {
        var base = String(
            title.lowercased().unicodeScalars.compactMap { scalar -> Character? in
                if scalar == " " { return "-" }
                if scalar == "-" || scalar == "_" { return Character(scalar) }
                let properties = scalar.properties
                return properties.isAlphabetic || properties.numericType != nil ? Character(scalar) : nil
            })
        if base.isEmpty { base = "section" }
        let count = seen[base, default: 0]
        seen[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }
}
