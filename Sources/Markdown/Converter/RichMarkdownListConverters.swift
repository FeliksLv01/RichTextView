import Markdown
#if SWIFT_PACKAGE
import RichTextView
#endif

public final class RichMarkdownOrderedListConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = OrderedList.self
    public init() {}

    public func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        guard let list = markup as? OrderedList else { return context }
        return context.replacing(
            listKind: .ordered(start: Int(list.startIndex)),
            listLevel: context.listLevel + 1
        )
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        children
    }
}

public final class RichMarkdownUnorderedListConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = UnorderedList.self
    public init() {}

    public func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        context.replacing(listKind: .unordered, listLevel: context.listLevel + 1)
    }

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        children
    }
}

public final class RichMarkdownListItemConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = ListItem.self
    public init() {}

    public func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        let nodeType: RichContentNodeType
        let index: Int?
        switch context.listKind {
        case .ordered(let start):
            nodeType = .numberedList
            index = start + markup.indexInParent
        case .unordered:
            nodeType = .bulletedList
            index = nil
        case .none:
            return children
        }
        return [RichContentNode(
            id: context.nodeID,
            type: nodeType,
            content: RichListContent(level: context.listLevel, index: index),
            children: children
        )]
    }
}
