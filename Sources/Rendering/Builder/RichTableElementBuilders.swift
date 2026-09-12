import UIKit

final class RichTableSectionElement: RichElement, @unchecked Sendable {
    let isHeader: Bool
    let rows: [RichTableRowElement]

    init(id: String, isHeader: Bool, rows: [RichTableRowElement], revision: RichElementRevision) {
        self.isHeader = isHeader
        self.rows = rows
        super.init(id: id, revision: revision, display: .block)
    }
}

final class RichTableRowElement: RichElement, @unchecked Sendable {
    let cells: [RichTableCellElement]

    init(id: String, cells: [RichTableCellElement], revision: RichElementRevision) {
        self.cells = cells
        super.init(id: id, revision: revision, display: .block)
    }
}

final class RichTableCellElement: RichElement, @unchecked Sendable {
    let alignment: RichTableCellAlignment
    private let storedChildren: [RichElement]
    override var children: [RichElement] { storedChildren }

    init(
        id: String,
        alignment: RichTableCellAlignment,
        children: [RichElement],
        revision: RichElementRevision
    ) {
        self.alignment = alignment
        storedChildren = children
        super.init(id: id, revision: revision, display: .block)
    }
}

public final class RichTableElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.table
    public init() {}

    public func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement? {
        let sectionRows = children.compactMap { section -> [(RichTableRowElement, Bool)]? in
            guard let section = section as? RichTableSectionElement else { return nil }
            return section.rows.map { ($0, section.isHeader) }
        }.flatMap { $0 }
        let directRows = children.compactMap { ($0 as? RichTableRowElement).map { ($0, false) } }
        let rows = sectionRows + directRows
        guard let model = RichTableLayoutBuilder.make(
            id: node.id,
            rows: rows,
            constrainedWidth: context.constrainedWidth,
            style: context.configuration.tableStyle
        ) else { return nil }
        return RichAttachmentElement(
            id: node.id,
            metrics: RichAttachmentMetrics(size: model.viewportSize, verticalAlignment: .top),
            reuseIdentifier: RichTableViewProvider.reuseIdentifier,
            provider: RichTableViewProvider(model: model),
            copyText: model.copyText,
            isSelectable: true,
            display: .block,
            revision: RichElementRevision(
                layout: node.revision.layout,
                display: node.revision.display
            )
        )
    }
}

public final class RichTableHeadElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.tableHead
    public init() {}

    public func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement? {
        var rows = children.compactMap { $0 as? RichTableRowElement }
        let directCells = children.compactMap { $0 as? RichTableCellElement }
        if rows.isEmpty, !directCells.isEmpty {
            rows = [RichTableRowElement(
                id: "\(node.id)/row",
                cells: directCells,
                revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
            )]
        }
        return RichTableSectionElement(
            id: node.id,
            isHeader: true,
            rows: rows,
            revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
        )
    }
}

public final class RichTableBodyElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.tableBody
    public init() {}

    public func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement? {
        RichTableSectionElement(
            id: node.id,
            isHeader: false,
            rows: children.compactMap { $0 as? RichTableRowElement },
            revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
        )
    }
}

public final class RichTableRowElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.tableRow
    public init() {}

    public func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement? {
        RichTableRowElement(
            id: node.id,
            cells: children.compactMap { $0 as? RichTableCellElement },
            revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
        )
    }
}

public final class RichTableCellElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.tableCell
    public init() {}

    public func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement? {
        RichTableCellElement(
            id: node.id,
            alignment: node.content(as: RichTableCellContent.self)?.alignment ?? .natural,
            children: children,
            revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
        )
    }
}
