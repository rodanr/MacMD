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

    private var paragraphSpacing: CGFloat {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
            let style = paragraph.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        else { return 0 }
        return style.paragraphSpacing
    }

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(
            CGRect(
                x: -layoutFragmentFrame.minX, y: 0, width: containerWidth,
                height: layoutFragmentFrame.height + paragraphSpacing))
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
            // Span the paragraph spacing too, so consecutive quote lines form one continuous bar.
            let bar = CGRect(
                x: frame.minX + 1, y: frame.minY, width: Theme.quoteBarWidth, height: frame.height + paragraphSpacing)
            let corner = Theme.quoteBarWidth / 2
            context.setFillColor(palette.quoteBar.cgColor)
            context.addPath(CGPath(roundedRect: bar, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
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
