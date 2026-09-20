import UIKit

public final class RichLatexElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.math
    private struct Key: Hashable {
        let latex: String
        let pointSize: CGFloat
        let isBlock: Bool
        let color: UIColor
        let preview: Bool
    }
    private let lock = NSLock()
    private var layouts: [Key: RichLatexLayout] = [:]
    private var order: [Key] = []
    private var previous: [String: Key] = [:]

    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let content = node.content(as: RichMathContent.self) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if previous.count >= 512, previous[node.id] == nil { previous.removeAll(keepingCapacity: true) }
        let key = Key(latex: content.latex, pointSize: context.configuration.font.pointSize,
                      isBlock: content.isBlock, color: context.configuration.textColor.resolvedColor(with: .current), preview: context.streaming)
        if let layout = layouts[key] {
            previous[node.id] = key
            return RichLatexElement(id: node.id, latex: key.latex, isBlock: key.isBlock, layout: layout)
        }
        let exact = RichLatexLayout(latex: key.latex, pointSize: key.pointSize, isBlock: key.isBlock, color: key.color)
        let preview = exact == nil && context.streaming ? RichLatexPreview.complete(key.latex) : nil
        if let layout = exact ?? preview.flatMap({ RichLatexLayout(latex: $0, pointSize: key.pointSize, isBlock: key.isBlock, color: key.color) }) {
            if order.count == 512 {
                let removed = order.removeFirst()
                layouts.removeValue(forKey: removed)
                previous = previous.filter { $0.value != removed }
            }
            order.append(key)
            layouts[key] = layout
            previous[node.id] = key
            return RichLatexElement(id: node.id, latex: key.latex, isBlock: key.isBlock, layout: layout)
        }
        if context.streaming, let old = previous[node.id], key.latex.hasPrefix(old.latex),
           old.pointSize == key.pointSize, old.isBlock == key.isBlock, old.color == key.color,
           let layout = layouts[old] {
            return RichLatexElement(id: node.id, latex: old.latex, isBlock: old.isBlock, layout: layout)
        }
        previous.removeValue(forKey: node.id)
        return RichTextElement(id: node.id,
            attributedText: NSAttributedString(string: context.streaming ? "" : content.latex,
                attributes: [.font: context.configuration.font, .foregroundColor: context.configuration.textColor]),
            display: content.isBlock ? .block : .inline)
    }
}
