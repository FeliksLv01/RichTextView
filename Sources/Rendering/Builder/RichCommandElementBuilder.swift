import UIKit

public final class RichCommandElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.command
    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let command = node.content(as: RichCommandContent.self) else { return nil }
        let label = command.label.isEmpty ? command.content : command.label
        let text = NSAttributedString(
            string: label.isEmpty ? "" : "[\(label)]",
            attributes: [
                .font: context.configuration.font,
                .foregroundColor: context.configuration.commandTextColor,
                .paragraphStyle: richParagraphStyle(context.configuration)
            ]
        )
        return RichTextElement(id: node.id, attributedText: text)
    }
}
