import UIKit
import iosMath

public final class RichMathElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.math

    public init() {}

    public func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement? {
        guard let content = node.content(as: RichMathContent.self) else { return nil }
        let pointSize = context.configuration.font.pointSize
        let size = Self.measure(content.latex, pointSize: pointSize, isBlock: content.isBlock)
        return RichAttachmentElement(
            id: node.id,
            metrics: RichAttachmentMetrics(
                size: CGSize(
                    width: content.isBlock ? context.constrainedWidth : size.width,
                    height: size.height
                ),
                verticalAlignment: .baseline
            ),
            font: context.configuration.font,
            reuseIdentifier: RichMathViewProvider.reuseIdentifier,
            provider: RichMathViewProvider(
                latex: content.latex,
                pointSize: pointSize,
                textColor: context.configuration.textColor,
                isBlock: content.isBlock
            ),
            copyText: content.isBlock ? "$$\(content.latex)$$" : "\\(\(content.latex)\\)",
            accessibilityLabel: content.latex,
            isSelectable: true,
            display: content.isBlock ? .block : .inline,
            revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
        )
    }

    private static func measure(_ latex: String, pointSize: CGFloat, isBlock: Bool) -> CGSize {
        guard
            let list = MTMathListBuilder.build(from: latex),
            let font = MTFontManager.fontManager.font(withName: MTFontNameLatinModern, size: pointSize)
        else {
            return CGSize(width: max(pointSize, CGFloat(latex.count) * pointSize * 0.5), height: pointSize * 1.25)
        }
        let display = MTTypesetter.createLine(
            for: list,
            font: font,
            style: isBlock ? .display : .text
        )
        return CGSize(width: ceil(display.width), height: ceil(display.ascent + display.descent) + 1)
    }
}

final class RichMathViewProvider: RichAttachmentViewProvider, @unchecked Sendable {
    static let reuseIdentifier = "rich-math"

    private let latex: String
    private let pointSize: CGFloat
    private let textColor: UIColor
    private let isBlock: Bool

    init(latex: String, pointSize: CGFloat, textColor: UIColor, isBlock: Bool) {
        self.latex = latex
        self.pointSize = pointSize
        self.textColor = textColor
        self.isBlock = isBlock
    }

    @MainActor
    func makeView() -> UIView {
        let label = MTMathUILabel()
        updateView(label)
        return label
    }

    @MainActor
    func updateView(_ view: UIView) {
        guard let label = view as? MTMathUILabel else { return }
        label.latex = latex
        label.fontSize = pointSize
        label.textColor = textColor
        label.displayErrorInline = false
        label.mode = isBlock ? .display : .text
        label.textAlignment = isBlock ? .center : .left
        label.isAccessibilityElement = true
        label.accessibilityLabel = latex
    }
}
