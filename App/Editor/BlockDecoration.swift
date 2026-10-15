import AppKit

extension NSAttributedString.Key {
    /// Marks a paragraph that gets a custom background (code block, quote bar, rule).
    static let blockDecoration = NSAttributedString.Key("io.github.rodanr.macmd.blockDecoration")
}

/// How a paragraph is decorated by `DecoratedLayoutFragment`.
enum BlockDecoration: String {
    case codeFirst, codeMiddle, codeLast, codeSingle
    case quote
    case rule

    var isCode: Bool {
        switch self {
        case .codeFirst, .codeMiddle, .codeLast, .codeSingle: true
        case .quote, .rule: false
        }
    }

    static func code(line index: Int, of count: Int) -> BlockDecoration {
        switch (index, count) {
        case (_, 1): .codeSingle
        case (0, _): .codeFirst
        case (count - 1, _): .codeLast
        default: .codeMiddle
        }
    }
}

/// A layout fragment that paints block decorations behind its text.
final class DecoratedLayoutFragment: NSTextLayoutFragment {
    private var decoration: BlockDecoration = .quote
    private var palette = DecorationPalette()

    convenience init(
        textElement: NSTextElement, range: NSTextRange?, decoration: BlockDecoration, palette: DecorationPalette
    ) {
        self.init(textElement: textElement, range: range)
        self.decoration = decoration
        self.palette = palette
    }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    // TextKit 2's fragment frame already includes the paragraph's spacing after it (the last paragraph has
    // none), so decorations cover the frame; 1 pt either side leaves room for edges snapped to whole points.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(
            CGRect(x: -layoutFragmentFrame.minX, y: -1, width: containerWidth, height: layoutFragmentFrame.height + 2))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let frame = CGRect(
            x: point.x - layoutFragmentFrame.minX, y: point.y,
            width: containerWidth, height: layoutFragmentFrame.height)
        context.saveGState()
        switch decoration {
        case .codeFirst, .codeMiddle, .codeLast, .codeSingle:
            drawCodeBackground(in: frame, context: context)
        case .quote:
            // The fragment frame includes the paragraph spacing, so consecutive quote lines tile exactly.
            // Square segments with edges snapped to whole points abut without overlapping, which would
            // otherwise show as a darker seam through the translucent bar.
            let top = layoutFragmentFrame.minY.rounded() - layoutFragmentFrame.minY
            let bottom = layoutFragmentFrame.maxY.rounded() - layoutFragmentFrame.minY
            let bar = CGRect(x: frame.minX + 1, y: frame.minY + top, width: Theme.quoteBarWidth, height: bottom - top)
            context.setFillColor(palette.quoteBar.cgColor)
            context.fill(bar)
        case .rule:
            let y = (frame.midY).rounded() + 0.5
            context.setStrokeColor(palette.rule.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: frame.minX, y: y))
            context.addLine(to: CGPoint(x: frame.maxX, y: y))
            context.strokePath()
        }
        context.restoreGState()
        super.draw(at: point, in: context)
    }

    private func drawCodeBackground(in frame: CGRect, context: CGContext) {
        let radius = Theme.blockRadius
        let roundTop = decoration == .codeFirst || decoration == .codeSingle
        let roundBottom = decoration == .codeLast || decoration == .codeSingle
        // Extend square edges past the frame so adjacent lines join seamlessly.
        var rect = frame
        if !roundTop { rect.origin.y -= radius; rect.size.height += radius }
        if !roundBottom { rect.size.height += radius }
        context.clip(to: frame)
        context.setFillColor(palette.codeBackground.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }
}

/// Colors used for decorations, resolved for the current appearance.
struct DecorationPalette {
    var codeBackground: NSColor = .quaternarySystemFill
    var quoteBar: NSColor = .controlAccentColor
    var rule: NSColor = .separatorColor
}
