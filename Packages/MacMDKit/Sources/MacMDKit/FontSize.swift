import Foundation

/// The font size of the editor and Read mode text, in points, separate from the window zoom.
public enum FontSize {
    public static let standard = 16.0
    public static let range: ClosedRange<Double> = 10...36

    /// A typed or stored value made safe: whole points within `range`; anything unusable becomes the default.
    public static func sanitized(_ size: Double) -> Double {
        guard size.isFinite, size > 0 else { return standard }
        return min(max(size.rounded(), range.lowerBound), range.upperBound)
    }

    public static func bigger(than size: Double) -> Double { sanitized(size + 1) }
    public static func smaller(than size: Double) -> Double { sanitized(size - 1) }

    /// "16 pt", with a hint at the default and the limits.
    public static func describe(_ size: Double) -> String {
        let value = "\(Int(size.rounded())) pt"
        if abs(size - standard) < 0.01 { return "\(value) (default)" }
        if size >= range.upperBound - 0.01 { return "\(value) (largest)" }
        if size <= range.lowerBound + 0.01 { return "\(value) (smallest)" }
        return value
    }
}
