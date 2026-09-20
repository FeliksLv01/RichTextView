import UIKit

public final class RichNumberedListElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.numberedList
    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let list = node.content(as: RichListContent.self) else { return nil }
        return makeListElement(
            node: node,
            children: children,
            marker: "\(marker(level: list.level, index: list.index ?? 0)).",
            list: list,
            context: context
        )
    }

    private func marker(level: Int, index: Int) -> String {
        if level % 3 == 2 {
            var value = index
            var result = ""
            while value > 0 {
                value -= 1
                guard let scalar = UnicodeScalar(97 + value % 26) else { return String(index) }
                result = String(scalar) + result
                value /= 26
            }
            return result
        }
        if level % 3 == 0 {
            let values = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
            var value = index
            var result = ""
            for (number, symbol) in values {
                while value >= number {
                    result += symbol
                    value -= number
                }
            }
            return result
        }
        return String(index)
    }
}

public final class RichBulletedListElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.bulletedList
    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let list = node.content(as: RichListContent.self) else { return nil }
        let marker = list.level % 3 == 1 ? "•" : (list.level % 3 == 2 ? "◦" : "▪")
        return makeListElement(
            node: node,
            children: children,
            marker: marker,
            markerScale: list.level % 3 == 0 ? 0.4 : 1,
            list: list,
            context: context
        )
    }
}

private func makeListElement(
    node: RichContentNode,
    children: [RichElement],
    marker: String,
    markerScale: CGFloat = 1,
    list: RichListContent,
    context: RichContentRenderContext
) -> RichElement {
    let bodyFont = context.configuration.font
    let markerFont = bodyFont.withSize(bodyFont.pointSize * markerScale)
    let markerText = NSAttributedString(
        string: marker,
        attributes: [
            .font: markerFont,
            .baselineOffset: (bodyFont.xHeight - markerFont.capHeight) / 2,
            .foregroundColor: context.configuration.secondaryTextColor,
            .paragraphStyle: richParagraphStyle(context.configuration)
        ]
    )
    return RichContainerElement(
        id: node.id,
        children: children,
        spacing: context.configuration.metrics.blockSpacing,
        contentInsets: RichContainerInsets(left: CGFloat(list.level) * context.configuration.metrics.listIndent),
        decoration: .listMarker(attributedText: markerText, width: context.configuration.metrics.listIndent)
    )
}
