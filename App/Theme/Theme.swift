import AppKit

/// A complete visual theme: typography for the editor plus the id of the matching reader CSS.
///
/// Colors are dynamic `NSColor`s, so a theme adapts to light and dark appearance by itself.
struct Theme: Equatable, Sendable {
    enum ID: String, CaseIterable, Identifiable, Sendable {
        case paper, clean, mono
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .paper: "Paper"
            case .clean: "Clean"
            case .mono: "Mono"
            }
        }

        var summary: String {
            switch self {
            case .paper: "New York serif, ink on paper"
            case .clean: "SF Pro, crisp and neutral"
            case .mono: "SF Mono, focused writing"
            }
        }
    }

    let id: ID
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat

    init(id: ID, fontSize: CGFloat) {
        self.id = id
        self.fontSize = fontSize
        self.lineHeightMultiple = id == .mono ? 1.5 : 1.45
    }

    // MARK: Fonts

    var bodyFont: NSFont { font(size: fontSize, weight: .regular) }

    /// The width of "0" in the body font: one CSS `ch`, the unit of the line width setting.
    var characterWidth: CGFloat { ("0" as NSString).size(withAttributes: [.font: bodyFont]).width }

    var codeFont: NSFont { .monospacedSystemFont(ofSize: fontSize * 0.88, weight: .regular) }

    func headingFont(level: Int) -> NSFont {
        let scale: [CGFloat] = [1.9, 1.5, 1.25, 1.1, 1.0, 0.9]
        let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
        return font(size: (fontSize * scale[min(max(level, 1), 6) - 1]).rounded(), weight: weight)
    }

    private func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign =
            switch id {
            case .paper: .serif
            case .clean: .default
            case .mono: .monospaced
            }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    // MARK: Colors

    var background: NSColor {
        switch id {
        case .paper: .dynamic(light: 0xFAFAF8, dark: 0x1A1B1E)
        case .clean: .dynamic(light: 0xFFFFFF, dark: 0x1E1E20)
        case .mono: .dynamic(light: 0xF6F6F4, dark: 0x18191B)
        }
    }

    var text: NSColor {
        switch id {
        case .paper: .dynamic(light: 0x24262B, dark: 0xE4E2DD)
        case .clean: .dynamic(light: 0x1D1D1F, dark: 0xE5E5E7)
        case .mono: .dynamic(light: 0x222326, dark: 0xDCDCD8)
        }
    }

    var secondaryText: NSColor { text.withAlphaComponent(0.66) }
    /// Markdown punctuation: visible but quiet (decorative, ≥ 2:1).
    var syntaxMarker: NSColor { text.withAlphaComponent(0.38) }
    var accent: NSColor { .controlAccentColor }
    /// Bullets, numbers and task boxes: quiet like the text, so lists read as content, not chrome.
    var listMarker: NSColor { text.withAlphaComponent(0.5) }
    /// Links use the system accent, softened toward the text color in dark mode where pure accents glare.
    var link: NSColor {
        let text = self.text
        return NSColor(name: nil) { appearance in
            var resolved = NSColor.controlAccentColor
            appearance.performAsCurrentDrawingAppearance {
                let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                guard isDark, let ink = text.usingColorSpace(.sRGB) else { resolved = accent; return }
                resolved = accent.blended(withFraction: 0.35, of: ink) ?? accent
            }
            return resolved
        }
    }
    /// Code surface: the theme's ink at low alpha, like reader.css `--surface` (4.5 %, Mono 5 %; 6 % in dark).
    var codeBackground: NSColor {
        let text = self.text
        let lightAlpha: CGFloat = id == .mono ? 0.05 : 0.045
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            var ink = NSColor.black
            appearance.performAsCurrentDrawingAppearance { ink = text.usingColorSpace(.sRGB) ?? ink }
            return ink.withAlphaComponent(isDark ? 0.06 : lightAlpha)
        }
    }
    var quoteBar: NSColor { .controlAccentColor.withAlphaComponent(Self.quoteBarAlpha) }
    var rule: NSColor { text.withAlphaComponent(0.14) }
    var mathColor: NSColor { .dynamic(light: 0x7A4BC2, dark: 0xC3A6F2) }

    // MARK: Design tokens (docs/DESIGN.md; mirrored in reader.css)

    static let blockRadius: CGFloat = 10
    static let panelRadius: CGFloat = 14
    static let quoteBarWidth: CGFloat = 2.5
    static let quoteBarAlpha: CGFloat = 0.45
    static let codeInset: CGFloat = 12
    static let motion = 0.15
}

extension NSColor {
    /// A color that resolves to `light` or `dark` (RGB hex) depending on the effective appearance.
    static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
        }
    }
}
