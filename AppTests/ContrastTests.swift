import AppKit
import Testing

@testable import MacMD

/// WCAG contrast of the editor's text colors on its paper, for every theme and appearance.
@MainActor
@Suite struct ContrastTests {
    static func luminance(_ color: NSColor) -> Double {
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
    }

    /// `color` composited over `background`, resolved in `appearance`.
    static func contrast(_ color: NSColor, on background: NSColor, appearance: NSAppearance) -> Double {
        var ratio = 0.0
        appearance.performAsCurrentDrawingAppearance {
            guard let fg = color.usingColorSpace(.sRGB), let bg = background.usingColorSpace(.sRGB) else { return }
            let a = fg.alphaComponent
            let blended = NSColor(
                srgbRed: fg.redComponent * a + bg.redComponent * (1 - a),
                green: fg.greenComponent * a + bg.greenComponent * (1 - a),
                blue: fg.blueComponent * a + bg.blueComponent * (1 - a), alpha: 1)
            let (l1, l2) = (luminance(blended), luminance(bg))
            ratio = (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }
        return ratio
    }

    @Test(arguments: Theme.ID.allCases, [NSAppearance.Name.aqua, .darkAqua])
    func textColorsMeetTheirTargets(theme id: Theme.ID, appearanceName: NSAppearance.Name) throws {
        let theme = Theme(id: id, fontSize: 16)
        let appearance = try #require(NSAppearance(named: appearanceName))
        #expect(Self.contrast(theme.text, on: theme.background, appearance: appearance) >= 7)
        #expect(Self.contrast(theme.secondaryText, on: theme.background, appearance: appearance) >= 4.5)
        #expect(Self.contrast(theme.listMarker, on: theme.background, appearance: appearance) >= 3)
        // Syntax markers are decorative and redundant with styling, so they only need to stay visible.
        #expect(Self.contrast(theme.syntaxMarker, on: theme.background, appearance: appearance) >= 2)
    }
}
