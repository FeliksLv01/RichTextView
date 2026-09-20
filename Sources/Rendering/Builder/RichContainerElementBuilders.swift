
import UIKit

public final class RichRootElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.root
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children, spacing: context.configuration.metrics.blockSpacing)
    }
}

public final class RichParagraphElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.paragraph
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children)
    }
}

public final class RichInlineElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.inline
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(
            id: node.id,
            children: children,
            display: .inline
        )
    }
}

public final class RichHeadingElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.heading
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children)
    }
}

public final class RichCodeBlockElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.codeBlock
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        let content = node.content(as: RichCodeBlockContent.self) ?? RichCodeBlockContent()
        let code = node.children.map(\.plainText).joined().trimmingCharacters(in: .newlines)
        let presentation = context.resolver?.codeBlockPresentation(
            for: node,
            content: content,
            code: code,
            context: context
        ) ?? RichCodeBlockHighlighting.presentation(
            for: code,
            language: content.language,
            nodeID: node.id
        )
        let attributedCode = normalizedCode(
            presentation?.attributedCode ?? NSAttributedString(string: code),
            configuration: context.configuration
        )
        let insets = presentation?.contentInsets ?? context.configuration.codeBlockInsets
        let provider = RichCodeBlockViewProvider(
            attributedCode: attributedCode,
            code: code,
            language: content.language,
            backgroundColor: presentation?.backgroundColor ?? context.configuration.codeBlockBackgroundColor,
            contentInsets: insets,
            cornerRadius: presentation?.cornerRadius ?? context.configuration.codeBlockCornerRadius
        )
        let codeElement = RichAttachmentElement(
            id: node.children.first?.id ?? "\(node.id)/code",
            metrics: RichAttachmentMetrics(
                size: CGSize(
                    width: context.constrainedWidth,
                    height: provider.requiredHeight
                ),
                verticalAlignment: .top
            ),
            reuseIdentifier: RichCodeBlockViewProvider.reuseIdentifier,
            provider: provider,
            copyText: code,
            isSelectable: true,
            display: .block
        )
        return RichContainerElement(
            id: node.id,
            children: [codeElement]
        )
    }

    private func normalizedCode(
        _ attributedCode: NSAttributedString,
        configuration: RichContentRenderingConfiguration
    ) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: attributedCode)
        let range = NSRange(location: 0, length: text.length)
        let defaults: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: configuration.codeBlockTextColor,
            .paragraphStyle: codeParagraphStyle()
        ]
        for (key, value) in defaults {
            text.enumerateAttribute(key, in: range) { attribute, missingRange, _ in
                if attribute == nil {
                    text.addAttribute(key, value: value, range: missingRange)
                }
            }
        }
        return text
    }

    private func codeParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 22
        style.maximumLineHeight = 22
        style.lineBreakMode = .byClipping
        return style
    }
}

public final class RichDividerElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.divider
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichDividerElement(
            id: node.id,
            color: context.configuration.dividerColor,
            lineHeight: context.configuration.dividerHeight,
            extent: context.configuration.dividerExtent
        )
    }
}

public final class RichColumnsElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.columns
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children, spacing: context.configuration.metrics.blockSpacing)
    }
}

public final class RichColumnElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.column
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children, spacing: context.configuration.metrics.blockSpacing)
    }
}

public final class RichReferenceElementBuilder: RichContentElementBuilding {
    public let inputs = false
    public let nodeType = RichContentNodeType.reference
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children, spacing: context.configuration.metrics.blockSpacing)
    }
}
