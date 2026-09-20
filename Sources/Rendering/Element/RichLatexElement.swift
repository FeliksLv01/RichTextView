import CoreText
import UIKit
import iosMath

public final class RichLatexElement: RichTextElement, @unchecked Sendable {
    public let latex: String
    public let isBlock: Bool
    public var size: CGSize { layout.size }
    let layout: RichLatexLayout
    private let fittingLock = NSLock()
    private var fitted: (width: CGFloat, element: RichTextElement)?

    init(id: String, latex: String, isBlock: Bool, layout: RichLatexLayout) {
        self.latex = latex
        self.isBlock = isBlock
        self.layout = layout
        super.init(id: id, attributedText: RichLatexRun(layout: layout).attributedString,
                   copyText: isBlock ? "$$\(latex)$$" : "\\(\(latex)\\)", display: isBlock ? .block : .inline)
    }

    func fitting(width: CGFloat) -> RichTextElement {
        fittingLock.lock()
        defer { fittingLock.unlock() }
        if let fitted, fitted.width == width { return fitted.element }
        let element = RichTextElement(id: id, attributedText: RichLatexRun(layout: layout, width: width).attributedString,
                                      copyText: copyText, display: .block)
        fitted = (width, element)
        return element
    }
}

final class RichLatexLayout: @unchecked Sendable {
    let size: CGSize
    let ascent: CGFloat
    let descent: CGFloat
    private let display: MTMathListDisplay
    // ponytail: serialize drawing of iosMath's mutable display graph; no shared mutation escapes this object.
    private let drawLock = NSLock()

    init?(latex: String, pointSize: CGFloat, isBlock: Bool, color: UIColor) {
        guard let list = MTMathListBuilder.build(from: latex),
              let font = MTFontManager.fontManager.font(withName: MTFontNameLatinModern, size: pointSize) else { return nil }
        display = MTTypesetter.createLine(for: list, font: font, style: isBlock ? .display : .text)
        display.textColor = color
        ascent = ceil(display.ascent) + 1
        descent = ceil(display.descent) + 1
        size = CGSize(width: ceil(display.width), height: ascent + descent)
    }

    func draw(in context: CGContext) {
        drawLock.lock()
        defer { drawLock.unlock() }
        display.draw(context)
    }
}

final class RichLatexRun: @unchecked Sendable {
    static let attribute = NSAttributedString.Key("io.github.felikslv01.rich-text-view.latex")
    let layout: RichLatexLayout
    let width: CGFloat
    let scale: CGFloat
    var ascent: CGFloat { layout.ascent * scale }
    var descent: CGFloat { layout.descent * scale }

    init(layout: RichLatexLayout, width: CGFloat? = nil) {
        self.layout = layout
        self.width = width ?? layout.size.width
        scale = min(1, self.width / max(1, layout.size.width))
    }

    var attributedString: NSAttributedString {
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1,
            dealloc: { Unmanaged<RichLatexRun>.fromOpaque($0).release() },
            getAscent: { Unmanaged<RichLatexRun>.fromOpaque($0).takeUnretainedValue().ascent },
            getDescent: { Unmanaged<RichLatexRun>.fromOpaque($0).takeUnretainedValue().descent },
            getWidth: { Unmanaged<RichLatexRun>.fromOpaque($0).takeUnretainedValue().width })
        let reference = Unmanaged.passRetained(self).toOpaque()
        guard let delegate = CTRunDelegateCreate(&callbacks, reference) else {
            Unmanaged<RichLatexRun>.fromOpaque(reference).release()
            return NSAttributedString(string: "")
        }
        return NSAttributedString(string: "\u{FFFC}", attributes: [
            kCTRunDelegateAttributeName as NSAttributedString.Key: delegate,
            Self.attribute: self, .foregroundColor: UIColor.clear
        ])
    }

    func draw(in context: CGContext, baseline: CGPoint) {
        context.saveGState()
        context.translateBy(x: baseline.x + (width - layout.size.width * scale) / 2, y: baseline.y)
        context.scaleBy(x: scale, y: scale)
        layout.draw(in: context)
        context.restoreGState()
    }
}
