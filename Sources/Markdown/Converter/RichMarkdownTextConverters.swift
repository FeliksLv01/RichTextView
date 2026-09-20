import Markdown
#if SWIFT_PACKAGE
import RichTextView
#endif

public final class RichMarkdownTextConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Text.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let text = markup as? Text else { return [] }
        return [RichContentNode(
            id: context.nodeID,
            type: .text,
            content: RichTextContent(text: text.string, style: context.textStyle)
        )]
    }
}

public final class RichMarkdownStrongConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Strong.self
    public init() {}

    public func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        context.replacing(textStyle: context.textStyle.replacing(bold: true))
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        children
    }
}

public final class RichMarkdownEmphasisConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Emphasis.self
    public init() {}

    public func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        context.replacing(textStyle: context.textStyle.replacing(italic: true))
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        children
    }
}

public final class RichMarkdownStrikethroughConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Strikethrough.self
    public init() {}

    public func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        context.replacing(textStyle: context.textStyle.replacing(strikethrough: true))
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        children
    }
}

public final class RichMarkdownInlineCodeConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = InlineCode.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let code = markup as? InlineCode else { return [] }
        if code.code.hasPrefix("richmath:") {
            return [RichContentNode(
                id: context.nodeID,
                type: .math,
                content: RichMathContent(latex: String(code.code.dropFirst(9)), isBlock: false)
            )]
        }
        return [RichContentNode(
            id: context.nodeID,
            type: .text,
            content: RichTextContent(
                text: code.code,
                style: context.textStyle.replacing(code: true)
            )
        )]
    }
}

public final class RichMarkdownSoftBreakConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = SoftBreak.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        [RichContentNode(
            id: context.nodeID,
            type: .text,
            content: RichTextContent(text: "\n", style: context.textStyle)
        )]
    }
}

public final class RichMarkdownLineBreakConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = LineBreak.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        [RichContentNode(
            id: context.nodeID,
            type: .text,
            content: RichTextContent(text: "\n", style: context.textStyle)
        )]
    }
}

private extension RichTextStyle {
    func replacing(
        bold: Bool? = nil,
        italic: Bool? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        code: Bool? = nil
    ) -> RichTextStyle {
        RichTextStyle(
            bold: bold ?? self.bold,
            italic: italic ?? self.italic,
            underline: underline ?? self.underline,
            strikethrough: strikethrough ?? self.strikethrough,
            code: code ?? self.code,
            fontScale: fontScale,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor
        )
    }
}
