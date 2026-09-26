import UIKit

public final class RichLatexElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.math
    private struct Key: Hashable {
        let latex: String
        let pointSize: CGFloat
        let isBlock: Bool
        let color: UIColor
    }
    private let lock = NSLock()
    private var layouts: [Key: RichLatexLayout] = [:]
    private var order: [Key] = []

    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let content = node.content(as: RichMathContent.self) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        let key = Key(latex: content.latex, pointSize: context.configuration.font.pointSize,
                      isBlock: content.isBlock, color: context.configuration.textColor)
        if let layout = layouts[key] {
            return RichLatexElement(id: node.id, latex: key.latex, isBlock: key.isBlock, layout: layout)
        }
        let exact = RichLatexLayout(latex: key.latex, pointSize: key.pointSize, isBlock: key.isBlock, color: key.color)
        if let layout = exact {
            if order.count == 512 {
                let removed = order.removeFirst()
                layouts.removeValue(forKey: removed)
            }
            order.append(key)
            layouts[key] = layout
            return RichLatexElement(id: node.id, latex: key.latex, isBlock: key.isBlock, layout: layout)
        }
        return RichTextElement(id: node.id,
            attributedText: NSAttributedString(string: context.streaming ? "" : content.latex,
                attributes: [.font: context.configuration.font, .foregroundColor: context.configuration.textColor]),
            display: content.isBlock ? .block : .inline)
    }
}
