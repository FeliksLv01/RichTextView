import UIKit

public final class RichMentionElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.mention
    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let mention = node.content(as: RichMentionContent.self) else { return nil }
        let presentation = context.resolver?.mentionPresentation(for: node, content: mention)
        let displayText = presentation?.displayText ?? "@\(mention.name)"
        let isHighlighted = presentation?.isHighlighted
            ?? context.configuration.highlightedMentionIDs.contains(mention.id)
        let element: RichElement
        if isHighlighted {
            let badgeHeight = ceil(context.configuration.lineHeight)
            let verticalInset = max(1, (badgeHeight - context.configuration.font.lineHeight) / 2)
            let spacing = context.configuration.mentionSpacing
            element = RichTextBadgeElement(
                id: node.id,
                text: displayText,
                font: context.configuration.font,
                foregroundColor: context.configuration.currentMentionTextColor,
                backgroundColor: context.configuration.currentMentionBackgroundColor,
                contentInsets: UIEdgeInsets(top: verticalInset, left: 6, bottom: verticalInset, right: 6),
                outerInsets: UIEdgeInsets(
                    top: 0,
                    left: context.needsLeadingInlineSpacing ? spacing : 0,
                    bottom: 0,
                    right: context.needsTrailingInlineSpacing ? spacing : 0
                ),
                cornerRadius: badgeHeight / 2,
                actionIdentifier: "mention:\(mention.id)",
                copyText: displayText
            )
        } else {
            element = RichTextBadgeElement(
                id: node.id,
                text: displayText,
                font: context.configuration.font,
                foregroundColor: presentation?.foregroundColor ?? context.configuration.linkColor,
                backgroundColor: .clear,
                contentInsets: .zero,
                cornerRadius: 0,
                actionIdentifier: "mention:\(mention.id)",
                copyText: displayText
            )
        }
        guard let trailing = presentation?.trailingElement else { return element }
        // Word Joiner makes the mention badge and its trailing status an atomic
        // line-breaking unit while keeping their render/action segments separate.
        let joiner = RichTextElement(
            id: "\(node.id)-mention-joiner",
            attributedText: NSAttributedString(string: "\u{2060}"),
            copyText: ""
        )
        return RichContainerElement(
            id: "\(node.id)-mention",
            children: [element, joiner, trailing],
            display: .inline
        )
    }
}
