import Markdown

public final class RichMarkdownTableConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Table.self
    public init() {}
    public func convert(_ markup: any Markup, children: [RichContentNode], context: RichMarkdownConversionContext) -> [RichContentNode] {
        [RichContentNode(id: context.nodeID, type: .table, children: children)]
    }
}

public final class RichMarkdownTableHeadConverter: RichMarkdownNodeConverting {
    public let markupType: Any.Type = Table.Head.self
    public init() {}
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
        [RichContentNode(id: context.nodeID, type: .tableCell, children: children)]
    }
}
