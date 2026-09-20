import UIKit

struct RichTableCellLayout: Sendable {
    let id: String
    let snapshot: RichElementSnapshot
    let layout: RichTextLayout
    let frame: CGRect
    let isHeader: Bool
}

struct RichTableLayoutModel: @unchecked Sendable {
    let id: String
    let cells: [RichTableCellLayout]
    let columnEdges: [CGFloat]
    let rowEdges: [CGFloat]
    let headerRowFrames: [CGRect]
    let viewportSize: CGSize
    let contentSize: CGSize
    let style: RichTableStyle
    let copyText: String
}

enum RichTableLayoutBuilder {
    private static let layoutEngine = RichTextLayoutEngine(cacheCapacity: 256)

    static func make(
        id: String,
        rows: [(RichTableRowElement, Bool)],
        constrainedWidth: CGFloat,
        style: RichTableStyle
    ) -> RichTableLayoutModel? {
        let columnCount = rows.map { $0.0.cells.count }.max() ?? 0
        guard columnCount > 0, constrainedWidth > 0 else { return nil }
        let maximumContentWidth = max(
            1,
            style.maximumColumnWidth - style.cellInsets.left - style.cellInsets.right
        )
        var preparedRows: [(cells: [PreparedCell], isHeader: Bool)] = []
        var columnWidths = Array(repeating: style.minimumColumnWidth, count: columnCount)

        for (row, isHeader) in rows {
            let cells = row.cells.enumerated().map { index, cell in
                let alignedSnapshot = snapshot(for: cell)
                let intrinsicLayout = layoutEngine.layout(
                    snapshot: snapshot(for: cell, appliesAlignment: false),
                    constrainedTo: CGSize(width: maximumContentWidth, height: .greatestFiniteMagnitude)
                )
                let width = min(
                    style.maximumColumnWidth,
                    max(
                        style.minimumColumnWidth,
                        intrinsicLayout.contentSize.width + style.cellInsets.left + style.cellInsets.right
                    )
                )
                columnWidths[index] = max(columnWidths[index], width)
                return PreparedCell(id: cell.id, snapshot: alignedSnapshot)
            }
            preparedRows.append((cells, isHeader))
        }

        var cells: [RichTableCellLayout] = []
        var rowEdges: [CGFloat] = [0]
        var headerRowFrames: [CGRect] = []
        var y: CGFloat = 0
        let contentWidth = columnWidths.reduce(0, +)
        for row in preparedRows {
            var layouts: [(PreparedCell, RichTextLayout)] = []
            var rowHeight = style.minimumRowHeight
            for (index, cell) in row.cells.enumerated() {
                let width = max(
                    1,
                    columnWidths[index] - style.cellInsets.left - style.cellInsets.right
                )
                let layout = layoutEngine.layout(
                    snapshot: cell.snapshot,
                    constrainedTo: CGSize(width: width, height: .greatestFiniteMagnitude)
                )
                rowHeight = max(
                    rowHeight,
                    layout.contentSize.height + style.cellInsets.top + style.cellInsets.bottom
                )
                layouts.append((cell, layout))
            }
            rowHeight = ceil(rowHeight)
            if row.isHeader {
                headerRowFrames.append(CGRect(x: 0, y: y, width: contentWidth, height: rowHeight))
            }
            var x: CGFloat = 0
            for (index, value) in layouts.enumerated() {
                let width = columnWidths[index]
                let frame = CGRect(
                    x: x + style.cellInsets.left,
                    y: y + style.cellInsets.top,
                    width: max(1, width - style.cellInsets.left - style.cellInsets.right),
                    height: max(1, rowHeight - style.cellInsets.top - style.cellInsets.bottom)
                )
                cells.append(RichTableCellLayout(
                    id: value.0.id,
                    snapshot: value.0.snapshot,
                    layout: value.1,
                    frame: frame,
                    isHeader: row.isHeader
                ))
                x += width
            }
            y += rowHeight
            rowEdges.append(y)
        }

        var columnEdges: [CGFloat] = [0]
        for width in columnWidths {
            columnEdges.append((columnEdges.last ?? 0) + width)
        }
        return RichTableLayoutModel(
            id: id,
            cells: cells,
            columnEdges: columnEdges,
            rowEdges: rowEdges,
            headerRowFrames: headerRowFrames,
            viewportSize: CGSize(width: min(constrainedWidth, contentWidth), height: y),
            contentSize: CGSize(width: contentWidth, height: y),
            style: style,
            copyText: copyText(rows: rows)
        )
    }

    private struct PreparedCell {
        let id: String
        let snapshot: RichElementSnapshot
    }

    private static func snapshot(
        for cell: RichTableCellElement,
        appliesAlignment: Bool = true
    ) -> RichElementSnapshot {
        let children = !appliesAlignment || cell.alignment == .natural
            ? cell.children
            : cell.children.map { applying(cell.alignment, to: $0) }
        return RichElementSnapshot(root: RichContainerElement(
            id: "\(cell.id)/table-cell-root",
            children: children
        ))
    }

    private static func applying(_ alignment: RichTableCellAlignment, to element: RichElement) -> RichElement {
        if let anchor = element as? RichAnchorElement {
            return RichAnchorElement(
                id: anchor.id,
                attributedText: applying(alignment, to: anchor.attributedText),
                actionIdentifier: anchor.actionIdentifier,
                copyText: anchor.copyText,
                maximumNumberOfLines: anchor.maximumNumberOfLines,
                lineBreakMode: .byCharWrapping,
                display: anchor.display
            )
        }
        if let text = element as? RichTextElement {
            return RichTextElement(
                id: text.id,
                attributedText: applying(alignment, to: text.attributedText),
                copyText: text.copyText,
                maximumNumberOfLines: text.maximumNumberOfLines,
                lineBreakMode: .byCharWrapping,
                display: text.display
            )
        }
        if let container = element as? RichContainerElement {
            return RichContainerElement(
                id: container.id,
                children: container.children.map { applying(alignment, to: $0) },
                display: container.display,
                spacing: container.spacing,
                contentInsets: container.contentInsets,
                decoration: container.decoration
            )
        }
        return element
    }

    private static func applying(
        _ alignment: RichTableCellAlignment,
        to text: NSAttributedString
    ) -> NSAttributedString {
        let value = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: value.length)
        guard range.length > 0 else { return value }
        let textAlignment: NSTextAlignment
        switch alignment {
        case .natural: return value
        case .left: textAlignment = .left
        case .center: textAlignment = .center
        case .right: textAlignment = .right
        }
        var styles: [(NSRange, NSMutableParagraphStyle)] = []
        value.enumerateAttribute(.paragraphStyle, in: range) { attribute, range, _ in
            let style = (attribute as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            style.alignment = textAlignment
            style.lineBreakMode = .byCharWrapping
            styles.append((range, style))
        }
        for (range, style) in styles {
            value.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return value
    }

    private static func copyText(rows: [(RichTableRowElement, Bool)]) -> String {
        rows.map { row, _ in
            row.cells.map { cell in
                cell.children.map(copyText).joined()
            }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private static func copyText(_ element: RichElement) -> String {
        if let text = element as? RichTextElement { return text.copyText }
        if let badge = element as? RichTextBadgeElement { return badge.copyText }
        if let image = element as? RichImageElement { return image.copyText ?? "" }
        if let attachment = element as? RichAttachmentElement { return attachment.copyText ?? "" }
        return element.children.map(copyText).joined()
    }
}

final class RichTableViewProvider: RichAttachmentViewProvider, @unchecked Sendable {
    static let reuseIdentifier = "RichTextView.Table"
    let model: RichTableLayoutModel

    init(model: RichTableLayoutModel) {
        self.model = model
    }

    @MainActor
    func makeView() -> UIView {
        RichTableView()
    }

    @MainActor
    func updateView(_ view: UIView) {
        (view as? RichTableView)?.apply(model)
    }

    @MainActor
    func prepareForReuse(_ view: UIView) {
        (view as? RichTableView)?.prepareForReuse()
    }
}

@MainActor
private final class RichTableView: UIView {
    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = false
        view.isDirectionalLockEnabled = true
        view.contentInsetAdjustmentBehavior = .never
        return view
    }()
    private let contentView = UIView()
    private let gridView = RichTableGridView()
    private var cellViews: [String: RichTextView] = [:]
    private var model: RichTableLayoutModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(gridView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func apply(_ model: RichTableLayoutModel) {
        self.model = model
        layer.cornerRadius = model.style.cornerRadius
        layer.borderWidth = model.style.borderWidth
        layer.borderColor = model.style.borderColor.resolvedColor(with: traitCollection).cgColor
        let requiredIDs = Set(model.cells.map(\.id))
        for id in cellViews.keys where !requiredIDs.contains(id) {
            cellViews.removeValue(forKey: id)?.removeFromSuperview()
        }
        for cell in model.cells {
            let view = cellViews[cell.id] ?? makeCellView(id: cell.id)
            view.frame = cell.frame
            view.apply(cell.snapshot, layout: cell.layout)
        }
        gridView.apply(model)
        setNeedsLayout()
    }

    func prepareForReuse() {
        cellViews.values.forEach {
            $0.prepareForReuse()
            $0.removeFromSuperview()
        }
        cellViews.removeAll(keepingCapacity: true)
        model = nil
        scrollView.contentOffset = .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let model else { return }
        scrollView.frame = bounds
        scrollView.contentSize = model.contentSize
        contentView.frame = CGRect(origin: .zero, size: model.contentSize)
        gridView.frame = contentView.bounds
        let maximumOffset = max(0, model.contentSize.width - bounds.width)
        if scrollView.contentOffset.x > maximumOffset {
            scrollView.contentOffset.x = maximumOffset
        }
        scrollView.showsHorizontalScrollIndicator = maximumOffset > 0.5
        scrollView.isScrollEnabled = maximumOffset > 0.5
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil,
              let model,
              model.contentSize.width > model.viewportSize.width + 0.5 else { return }
        scrollView.flashScrollIndicators()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
              let model else { return }
        layer.borderColor = model.style.borderColor.resolvedColor(with: traitCollection).cgColor
        gridView.setNeedsDisplay()
    }

    private func makeCellView(id: String) -> RichTextView {
        let view = RichTextView()
        view.backgroundColor = .clear
        view.laysOutAsynchronously = false
        view.actionHandler = { [weak self] _, identifier in
            self?.parentRichTextView?.activate(identifier)
        }
        contentView.addSubview(view)
        cellViews[id] = view
        return view
    }

    private var parentRichTextView: RichTextView? {
        var view = superview
        while let current = view {
            if let richTextView = current as? RichTextView { return richTextView }
            view = current.superview
        }
        return nil
    }
}

@MainActor
private final class RichTableGridView: UIView {
    private var model: RichTableLayoutModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func apply(_ model: RichTableLayoutModel) {
        self.model = model
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let model, let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(model.style.headerBackgroundColor.resolvedColor(with: traitCollection).cgColor)
        for frame in model.headerRowFrames {
            context.fill(frame)
        }
        context.setStrokeColor(model.style.borderColor.resolvedColor(with: traitCollection).cgColor)
        context.setLineWidth(model.style.borderWidth)
        for x in model.columnEdges.dropFirst().dropLast() {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: model.contentSize.height))
        }
        for y in model.rowEdges.dropFirst().dropLast() {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: model.contentSize.width, y: y))
        }
        context.strokePath()
    }
}
