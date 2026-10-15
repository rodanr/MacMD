import Foundation

/// Window zoom: one factor that scales the editor, Read mode, sidebar and status bar together.
/// Steps follow Safari's, so ⌘+ and ⌘- feel familiar.
public enum Zoom {
    public static let levels: [Double] = [0.75, 0.85, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
    public static let actualSize = 1.0

    public static var range: ClosedRange<Double> { levels[0]...levels[levels.count - 1] }

    public static func zoomedIn(from zoom: Double) -> Double {
        levels.first { $0 > zoom + 0.001 } ?? range.upperBound
    }

    public static func zoomedOut(from zoom: Double) -> Double {
        levels.last { $0 < zoom - 0.001 } ?? range.lowerBound
    }

    /// A stored value made safe: anything outside the range (or not a number) becomes 100%.
    public static func sanitized(_ zoom: Double) -> Double {
        range.contains(zoom) ? zoom : actualSize
    }

    /// "110%".
    public static func percent(_ zoom: Double) -> String { "\(Int((zoom * 100).rounded()))%" }

    /// "110%", with a hint at 100% and at the limits.
    public static func describe(_ zoom: Double) -> String {
        let value = percent(zoom)
        if abs(zoom - actualSize) < 0.001 { return "\(value) (actual size)" }
        if zoom >= range.upperBound - 0.001 { return "\(value) (largest)" }
        if zoom <= range.lowerBound + 0.001 { return "\(value) (smallest)" }
        return value
    }
}
