import UIKit

public final class RichImageElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.image

    public init() {}

    public func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement? {
        guard let content = node.content(as: RichImageContent.self) else { return nil }
        guard let source = context.resolver?.imageSource(for: node, content: content) else {
            let fallback = content.title.isEmpty ? content.source : content.title
            return RichTextElement(
                id: node.id,
                attributedText: NSAttributedString(
                    string: fallback,
                    attributes: [
                        .font: context.configuration.font,
                        .foregroundColor: context.configuration.secondaryTextColor,
                        .paragraphStyle: richParagraphStyle(context.configuration)
                    ]
                ),
                copyText: fallback
            )
        }
        return RichImageElement(
            id: node.id,
            source: source,
            size: content.size,
            font: context.configuration.font,
            copyText: content.title,
            accessibilityLabel: content.title
        )
    }
}
