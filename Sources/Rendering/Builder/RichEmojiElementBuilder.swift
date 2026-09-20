import UIKit

public final class RichEmojiElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.emoji
    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let emoji = node.content(as: RichEmojiContent.self) else { return nil }
        if let image = context.resolver?.emojiPresentation(for: node, content: emoji) {
            return RichImageElement(
                id: node.id,
                source: image.source,
                size: image.size,
                contentInsets: image.contentInsets,
                font: context.configuration.font,
                copyText: image.copyText,
                accessibilityLabel: image.accessibilityLabel
            )
        }
        let text = NSAttributedString(
            string: emoji.name.isEmpty ? emoji.code : emoji.name,
            attributes: [
                .font: context.configuration.font,
                .foregroundColor: context.configuration.textColor,
                .paragraphStyle: richParagraphStyle(context.configuration)
            ]
        )
        return RichTextElement(id: node.id, attributedText: text)
    }
}
