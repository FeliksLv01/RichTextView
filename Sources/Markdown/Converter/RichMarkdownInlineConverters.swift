import CoreGraphics
import Markdown
#if SWIFT_PACKAGE
import RichTextView
#endif

public final class RichMarkdownLinkConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Link.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let link = markup as? Link else { return children }
        return [RichContentNode(
            id: context.nodeID,
            type: .link,
            content: RichLinkContent(
                href: link.destination ?? "",
                title: link.title ?? "",
                icon: ""
            ),
            children: children
        )]
    }
}

public final class RichMarkdownImageConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Image.self
    private let imageSize: CGSize

    public init(imageSize: CGSize) {
        precondition(imageSize.width > 0 && imageSize.height > 0, "Markdown image size must be positive")
        self.imageSize = imageSize
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let image = markup as? Image else { return [] }
        let title = children.compactMap { $0.content(as: RichTextContent.self)?.text }.joined()
        return [RichContentNode(
            id: context.nodeID,
            type: .image,
            content: RichImageContent(
                source: image.source ?? "",
                title: image.title ?? title,
                size: imageSize
            )
        )]
    }
}

public final class RichMarkdownInlineHTMLConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = InlineHTML.self
    private let resolver: (any RichMarkdownHTMLResolving)?

    public init(resolver: (any RichMarkdownHTMLResolving)? = nil) {
        self.resolver = resolver
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let html = markup as? InlineHTML else { return [] }
        return resolver?.resolve(literal: html.rawHTML, isBlock: false, context: context)
            ?? [RichContentNode(
                id: context.nodeID,
                type: .markdownHTML,
                content: RichMarkdownLiteralContent(literal: html.rawHTML)
            )]
    }
}

public final class RichMarkdownHTMLBlockConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = HTMLBlock.self
    private let resolver: (any RichMarkdownHTMLResolving)?

    public init(resolver: (any RichMarkdownHTMLResolving)? = nil) {
        self.resolver = resolver
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let html = markup as? HTMLBlock else { return [] }
        return resolver?.resolve(literal: html.rawHTML, isBlock: true, context: context)
            ?? [RichContentNode(
                id: context.nodeID,
                type: .markdownHTML,
                content: RichMarkdownLiteralContent(literal: html.rawHTML)
            )]
    }
}
