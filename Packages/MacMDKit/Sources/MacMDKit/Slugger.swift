/// Generates GitHub-compatible heading anchors, de-duplicating repeats (`intro`, `intro-1`, …).
public struct Slugger: Sendable {
    /// How many times each slug has been handed out, as in github-slugger.
    private var occurrences: [String: Int] = [:]

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
        var result = base
        // Skip suffixes another heading already uses: "Intro", "Intro 1", "Intro" give intro, intro-1, intro-2.
        while occurrences[result] != nil {
            occurrences[base, default: 0] += 1
            result = "\(base)-\(occurrences[base, default: 0])"
        }
        occurrences[result] = 0
        return result
    }
}
