
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
    private let maximumVisibleLines = 15

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
        let overflowBehavior = context.configuration.codeBlockOverflowBehavior
        let attributedCode = normalizedCode(
            presentation?.attributedCode ?? NSAttributedString(string: code),
            configuration: context.configuration,
            lineBreakMode: overflowBehavior == .wrapAndCollapse ? .byCharWrapping : .byClipping
        )
        let insets = presentation?.contentInsets ?? context.configuration.codeBlockInsets
        let backgroundColor = presentation?.backgroundColor ?? context.configuration.codeBlockBackgroundColor
        if overflowBehavior == .horizontalScroll {
            let provider = RichCodeBlockViewProvider(
                attributedCode: attributedCode,
                code: code,
                language: content.language,
                backgroundColor: backgroundColor,
                contentInsets: insets,
                cornerRadius: presentation?.cornerRadius ?? context.configuration.codeBlockCornerRadius
            )
            return RichContainerElement(
                id: node.id,
                children: [RichAttachmentElement(
                    id: node.children.first?.id ?? "\(node.id)/code",
                    metrics: RichAttachmentMetrics(
                        size: CGSize(width: context.constrainedWidth, height: provider.requiredHeight),
                        verticalAlignment: .top
                    ),
                    reuseIdentifier: RichCodeBlockViewProvider.reuseIdentifier,
                    provider: provider,
                    copyText: code,
                    isSelectable: true,
                    display: .block
                )]
            )
        }
        let availableWidth = max(1, context.constrainedWidth - insets.left - insets.right)
        let fullLayout = RichCoreTextLayout(
            attributedText: attributedCode,
            constrainedWidth: availableWidth,
            lineBreakMode: .byCharWrapping
        )
        let overflows = (fullLayout?.lines.count ?? 0) > maximumVisibleLines
        let visibleCode: NSAttributedString
        if content.isStreaming, overflows, let fullLayout {
            visibleCode = trailingLines(in: attributedCode, layout: fullLayout)
        } else {
            visibleCode = attributedCode
        }
        var codeElements: [RichElement] = []
        let language = content.language.trimmingCharacters(in: .whitespacesAndNewlines)
        codeElements.append(RichTextElement(
            id: node.children.first?.id ?? "\(node.id)/code",
            attributedText: visibleCode,
            copyText: code,
            maximumNumberOfLines: maximumVisibleLines,
            lineBreakMode: .byCharWrapping,
            display: .block
        ))
        if overflows, !content.isStreaming {
            codeElements.append(RichVerticalGradientElement(
                id: "\(node.id)/fade",
                topColor: backgroundColor.withAlphaComponent(0),
                bottomColor: backgroundColor,
                extent: 28
            ))
            let footerStyle = NSMutableParagraphStyle()
            footerStyle.alignment = .center
            footerStyle.minimumLineHeight = 28
            footerStyle.maximumLineHeight = 28
            codeElements.append(RichAnchorElement(
                id: "\(node.id)/view-all",
                attributedText: NSAttributedString(
                    string: localizedString("rich_code_view_full"),
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: context.configuration.codeBlockTextColor.withAlphaComponent(0.9),
                        .paragraphStyle: footerStyle
                    ]
                ),
                actionIdentifier: "code-block:\(node.id)",
                copyText: "",
                display: .block
            ))
        }
        var elements: [RichElement] = []
        if !language.isEmpty {
            elements.append(codeHeader(
                nodeID: node.id,
                language: language,
                width: context.constrainedWidth,
                configuration: context.configuration,
                cornerRadius: presentation?.cornerRadius ?? context.configuration.codeBlockCornerRadius
            ))
            elements.append(RichDividerElement(
                id: "\(node.id)/header-divider",
                color: context.configuration.codeBlockTextColor.withAlphaComponent(0.14),
                lineHeight: 1,
                extent: 1
            ))
        }
        elements.append(RichContainerElement(
            id: "\(node.id)/body",
            children: codeElements,
            contentInsets: insets
        ))
        return RichContainerElement(
            id: node.id,
            children: elements,
            decoration: .borderedBackground(
                color: backgroundColor,
                cornerRadius: presentation?.cornerRadius ?? context.configuration.codeBlockCornerRadius,
                borderColor: context.configuration.codeBlockTextColor.withAlphaComponent(0.14),
                borderWidth: 1
            )
        )
    }

    private func normalizedCode(
        _ attributedCode: NSAttributedString,
        configuration: RichContentRenderingConfiguration,
        lineBreakMode: NSLineBreakMode
    ) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: attributedCode)
        let range = NSRange(location: 0, length: text.length)
        let defaults: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: configuration.codeBlockTextColor,
            .paragraphStyle: codeParagraphStyle(lineBreakMode: lineBreakMode)
        ]
        for (key, value) in defaults {
            text.enumerateAttribute(key, in: range) { attribute, missingRange, _ in
                if attribute == nil {
                    text.addAttribute(key, value: value, range: missingRange)
                }
            }
        }
        text.enumerateAttribute(.paragraphStyle, in: range) { value, paragraphRange, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? codeParagraphStyle(lineBreakMode: lineBreakMode)
            style.lineBreakMode = lineBreakMode
            text.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
        }
        return text
    }

    private func codeParagraphStyle(lineBreakMode: NSLineBreakMode) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 22
        style.maximumLineHeight = 22
        style.lineBreakMode = lineBreakMode
        return style
    }

    private func trailingLines(
        in attributedCode: NSAttributedString,
        layout: RichCoreTextLayout
    ) -> NSAttributedString {
        guard let first = layout.lines.suffix(maximumVisibleLines).first else { return attributedCode }
        return attributedCode.attributedSubstring(from: NSRange(
            location: first.range.location,
            length: attributedCode.length - first.range.location
        ))
    }

    private func codeHeader(
        nodeID: String,
        language: String,
        width: CGFloat,
        configuration: RichContentRenderingConfiguration,
        cornerRadius: CGFloat
    ) -> RichContainerElement {
        let font = UIFont.systemFont(ofSize: 13, weight: .medium)
        let insets = RichContainerInsets(left: 16, right: 4)
        let contentWidth = max(1, width - insets.left - insets.right)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 30
        style.maximumLineHeight = 30
        style.lineBreakMode = .byClipping
        style.tabStops = [NSTextTab(textAlignment: .right, location: max(0, contentWidth - 10))]
        let label = RichTextElement(
            id: "\(nodeID)/language",
            attributedText: NSAttributedString(
                string: language.prefix(1).uppercased() + language.dropFirst() + "\t",
                attributes: [
                    .font: font,
                    .foregroundColor: configuration.codeBlockTextColor,
                    .paragraphStyle: style
                ]
            ),
            copyText: ""
        )
        let icon = UIImage(
            systemName: "doc.on.doc",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        )
        let copy = RichImageElement(
            id: "\(nodeID)/copy",
            source: RichImageSource(identifier: "\(nodeID)/copy-icon", image: icon),
            size: CGSize(width: 24, height: 24),
            font: font,
            tintColor: configuration.codeBlockTextColor.withAlphaComponent(0.7),
            copyText: "",
            accessibilityLabel: "Copy",
            actionIdentifier: "copy-code:\(nodeID)"
        )
        return RichContainerElement(
            id: "\(nodeID)/header",
            children: [label, copy],
            contentInsets: insets,
            decoration: .topRoundedBackground(
                color: configuration.codeBlockTextColor.withAlphaComponent(0.08),
                cornerRadius: cornerRadius
            )
        )
    }

    private func localizedString(_ key: String) -> String {
        #if SWIFT_PACKAGE
        let resourceBundle = Bundle.module
        #else
        let containingBundle = Bundle(for: RichCodeBlockElementBuilder.self)
        let resourceBundle = [containingBundle, .main].lazy.compactMap { bundle -> Bundle? in
            guard let url = bundle.url(forResource: "RichTextViewResources", withExtension: "bundle") else { return nil }
            return Bundle(url: url)
        }.first ?? containingBundle
        #endif
        let localization = Bundle.preferredLocalizations(
            from: resourceBundle.localizations,
            forPreferences: Locale.preferredLanguages
        ).first
        guard let localization,
              let path = resourceBundle.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return resourceBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
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
