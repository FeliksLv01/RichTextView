import Markdown
#if SWIFT_PACKAGE
import RichTextView
#endif

public final class RichMarkdownTableConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Table.self
    public init() {}
    public func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        guard let table = markup as? Table else { return context }
        return context.replacing(tableColumnAlignments: table.columnAlignments.map { alignment in
            guard let alignment else { return .natural }
            switch alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            @unknown default: return .natural
            }
        })
    }
    public func convert(_ markup: any Markup, children: [RichContentNode], context: RichMarkdownConversionContext) -> [RichContentNode] {
        [RichContentNode(id: context.nodeID, type: .table, children: children)]
    }
}

public final class RichMarkdownTableHeadConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Table.Head.self
    public init() {}
    public func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        let style = context.textStyle
        return context.replacing(textStyle: RichTextStyle(
            bold: true,
            italic: style.italic,
            underline: style.underline,
            strikethrough: style.strikethrough,
            code: style.code,
            fontScale: style.fontScale,
            foregroundColor: style.foregroundColor,
            backgroundColor: style.backgroundColor
        ))
    }
    public func convert(_ markup: any Markup, children: [RichContentNode], context: RichMarkdownConversionContext) -> [RichContentNode] {
        [RichContentNode(id: context.nodeID, type: .tableHead, children: children)]
    }
}

public final class RichMarkdownTableBodyConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Table.Body.self
    public init() {}
    public func convert(_ markup: any Markup, children: [RichContentNode], context: RichMarkdownConversionContext) -> [RichContentNode] {
        [RichContentNode(id: context.nodeID, type: .tableBody, children: children)]
    }
}

public final class RichMarkdownTableRowConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Table.Row.self
    public init() {}
    public func convert(_ markup: any Markup, children: [RichContentNode], context: RichMarkdownConversionContext) -> [RichContentNode] {
        [RichContentNode(id: context.nodeID, type: .tableRow, children: children)]
    }
}

public final class RichMarkdownTableCellConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Table.Cell.self
    public init() {}
    public func convert(_ markup: any Markup, children: [RichContentNode], context: RichMarkdownConversionContext) -> [RichContentNode] {
        guard let cell = markup as? Table.Cell else { return [] }
        return [RichContentNode(
            id: context.nodeID,
            type: .tableCell,
            content: RichTableCellContent(alignment: alignment(for: cell, context: context)),
            children: children
        )]
    }

    private func alignment(
        for cell: Table.Cell,
        context: RichMarkdownConversionContext
    ) -> RichTableCellAlignment {
        guard context.tableColumnAlignments.indices.contains(cell.indexInParent) else { return .natural }
        return context.tableColumnAlignments[cell.indexInParent]
    }
}
