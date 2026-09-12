import UIKit

public final class RichLinkElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.link
    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let link = node.content(as: RichLinkContent.self) else { return nil }
        let text = NSMutableAttributedString()
        for child in children {
            guard let textChild = child as? RichTextElement else { continue }
            text.append(textChild.attributedText)
        }
        if text.length == 0 {
            let resolvedTitle = context.resolver?.resolvedLink(for: node, content: link)?.title
                ?? context.configuration.resolvedLinks[link.href]?.title
            text.append(NSAttributedString(
                string: resolvedTitle ?? (link.title.isEmpty ? link.href : link.title),
                attributes: [
                    .font: context.configuration.font,
                    .paragraphStyle: richParagraphStyle(context.configuration)
                ]
            ))
        }
        text.addAttribute(
            .foregroundColor,
            value: context.configuration.linkColor,
            range: NSRange(location: 0, length: text.length)
        )
        let anchor = RichAnchorElement(
            id: node.id,
            attributedText: text,
            actionIdentifier: "link:\(link.href)",
            copyText: text.string
        )
        guard let image = context.resolver?.linkIconPresentation(for: node, content: link) else { return anchor }
        let icon = RichImageElement(
            id: "\(node.id)-icon",
            source: image.source,
            size: image.size,
            contentInsets: image.contentInsets,
            font: context.configuration.font,
            copyText: image.copyText,
            accessibilityLabel: image.accessibilityLabel
        )
        return RichContainerElement(
            id: "\(node.id)-link-container",
            children: [icon, anchor],
            display: .inline
        )
    }
}
