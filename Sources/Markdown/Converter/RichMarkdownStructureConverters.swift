import Markdown
#if SWIFT_PACKAGE
import RichTextView
#endif

public final class RichMarkdownDocumentConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Document.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        [RichContentNode(id: context.documentID, type: .root, children: children)]
    }
}

public final class RichMarkdownParagraphConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Paragraph.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        [RichContentNode(id: context.nodeID, type: .paragraph, children: children)]
    }
}

public final class RichMarkdownHeadingConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Heading.self
    public init() {}

    public func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        guard let heading = markup as? Heading else { return context }
        let fontScales = [1.5, 1.35, 1.25, 1.15, 1.08, 1]
        return context.replacing(textStyle: RichTextStyle(
            bold: true,
            italic: context.textStyle.italic,
            underline: context.textStyle.underline,
            strikethrough: context.textStyle.strikethrough,
            code: context.textStyle.code,
            fontScale: fontScales[min(max(heading.level, 1), 6) - 1],
            foregroundColor: context.textStyle.foregroundColor,
            backgroundColor: context.textStyle.backgroundColor
        ))
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let heading = markup as? Heading else { return children }
        return [RichContentNode(
            id: context.nodeID,
            type: .heading,
            content: RichHeadingContent(level: heading.level),
            children: children
        )]
    }
}

public final class RichMarkdownBlockQuoteConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = BlockQuote.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        [RichContentNode(id: context.nodeID, type: .blockQuote, children: children)]
    }
}

public final class RichMarkdownCodeBlockConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = CodeBlock.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let codeBlock = markup as? CodeBlock else { return [] }
        let style = RichTextStyle(
            bold: context.textStyle.bold,
            italic: context.textStyle.italic,
            underline: context.textStyle.underline,
            strikethrough: context.textStyle.strikethrough,
            code: true,
            fontScale: context.textStyle.fontScale,
            foregroundColor: context.textStyle.foregroundColor,
            backgroundColor: context.textStyle.backgroundColor
        )
        let text = RichContentNode(
            id: "\(context.nodeID)/text",
            type: .text,
            content: RichTextContent(text: codeBlock.code, style: style)
        )
        return [RichContentNode(
            id: context.nodeID,
            type: .codeBlock,
            content: RichCodeBlockContent(language: codeBlock.language ?? ""),
            children: [text]
        )]
    }
}

public final class RichMarkdownThematicBreakConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = ThematicBreak.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        [RichContentNode(id: context.nodeID, type: .divider)]
    }
}
