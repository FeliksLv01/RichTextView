import UIKit

struct RichTableCellLayout: Sendable {
    let snapshot: RichElementSnapshot
    let layout: RichTextLayout
    let frame: CGRect
}

struct RichTableLayoutModel: @unchecked Sendable {
    let id: String
    let rows: [[RichTableCellLayout]]
    let columnEdges: [CGFloat]
    let rowEdges: [CGFloat]
    let headerRows: IndexSet
    let viewportSize: CGSize
    let contentSize: CGSize
    let style: RichTableStyle
    let copyText: String
}

enum RichTableLayoutBuilder {
    static func make(
        id: String,
        rows: [(RichTableRowElement, Bool)],
        constrainedWidth: CGFloat,
        style: RichTableStyle
    ) -> RichTableLayoutModel? {
        let columnCount = rows.map { $0.0.cells.count }.max() ?? 0
        guard columnCount > 0, constrainedWidth > 0 else { return nil }
        let maximumContentWidth = style.maximumCellContentWidth
        var preparedRows: [(cells: [RichElementSnapshot], isHeader: Bool)] = []
        var columnWidths = Array(repeating: style.minimumColumnWidth, count: columnCount)

        for (row, isHeader) in rows {
            let cells = row.cells.enumerated().map { index, cell in
                let alignedSnapshot = snapshot(for: cell)
                let intrinsicLayout = RichTextLayoutEngine.shared.layout(
                    snapshot: snapshot(for: cell, appliesAlignment: false),
                    constrainedTo: CGSize(width: maximumContentWidth, height: .greatestFiniteMagnitude),
                    cachesLayouts: false
                )
                let width = min(
                    style.maximumColumnWidth,
                    max(
                        style.minimumColumnWidth,
                        intrinsicLayout.contentSize.width + style.cellInsets.left + style.cellInsets.right
                    )
                )
                columnWidths[index] = max(columnWidths[index], width)
                return alignedSnapshot
            }
            preparedRows.append((cells, isHeader))
        }

        var cellRows: [[RichTableCellLayout]] = []
        var rowEdges: [CGFloat] = [0]
        var headerRows = IndexSet()
        var y: CGFloat = 0
        let contentWidth = columnWidths.reduce(0, +)
        for row in preparedRows {
            var cells: [RichTableCellLayout] = []
            var layouts: [(RichElementSnapshot, RichTextLayout)] = []
            var rowHeight = style.minimumRowHeight
            for (index, cell) in row.cells.enumerated() {
                let width = max(
                    1,
                    columnWidths[index] - style.cellInsets.left - style.cellInsets.right
                )
                let layout = RichTextLayoutEngine.shared.layout(
                    snapshot: cell,
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
                headerRows.insert(cellRows.count)
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
                    snapshot: value.0,
                    layout: value.1,
                    frame: frame
                ))
                x += width
            }
            cellRows.append(cells)
            y += rowHeight
            rowEdges.append(y)
        }

        var columnEdges: [CGFloat] = [0]
        for width in columnWidths {
            columnEdges.append((columnEdges.last ?? 0) + width)
        }
        return RichTableLayoutModel(
            id: id,
            rows: cellRows,
            columnEdges: columnEdges,
            rowEdges: rowEdges,
            headerRows: headerRows,
            viewportSize: CGSize(width: min(constrainedWidth, contentWidth), height: y),
            contentSize: CGSize(width: contentWidth, height: y),
            style: style,
            copyText: copyText(rows: rows)
        )
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
                action: anchor.action,
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
            return container.replacingChildren(container.children.map { applying(alignment, to: $0) })
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
final class RichTableView: UIView {
    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.isDirectionalLockEnabled = true
        view.contentInsetAdjustmentBehavior = .never
        return view
    }()
    private(set) var canvas: RichTableCanvas?
    private var model: RichTableLayoutModel?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func apply(_ model: RichTableLayoutModel) {
        self.model = model
        let tiled = model.contentSize.width > 1024 || model.contentSize.height > 1024
        if canvas == nil || (canvas is RichTiledTableCanvas) != tiled {
            canvas?.removeFromSuperview()
            let view = tiled ? RichTiledTableCanvas() : RichTableCanvas()
            scrollView.addSubview(view)
            canvas = view
        }
        canvas?.frame = CGRect(origin: .zero, size: model.contentSize)
        canvas?.apply(model)
        layer.cornerRadius = model.style.cornerRadius
        layer.borderWidth = model.style.borderWidth
        layer.borderColor = model.style.borderColor.resolvedColor(with: traitCollection).cgColor
        setNeedsLayout()
    }

    func prepareForReuse() {
        canvas?.removeFromSuperview()
        canvas = nil
        model = nil
        scrollView.contentOffset = .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let model else { return }
        scrollView.frame = bounds
        scrollView.contentSize = model.contentSize
        let maximumOffset = max(0, model.contentSize.width - bounds.width)
        if scrollView.contentOffset.x > maximumOffset { scrollView.contentOffset.x = maximumOffset }
        scrollView.showsHorizontalScrollIndicator = maximumOffset > 0.5
        scrollView.isScrollEnabled = maximumOffset > 0.5
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, let model, model.contentSize.width > model.viewportSize.width + 0.5 else { return }
        scrollView.flashScrollIndicators()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
              let model else { return }
        layer.borderColor = model.style.borderColor.resolvedColor(with: traitCollection).cgColor
        canvas?.redraw(model, traits: traitCollection)
    }
}

private final class RichTableLayer: CALayer {
    var drawTable: ((CGContext) -> Void)?
    override func draw(in context: CGContext) { drawTable?(context) }
}

private final class RichTiledTableCanvas: RichTableCanvas {
    override class var layerClass: AnyClass { RichTiledLayer.self }
}

class RichTableCanvas: UIView, UIGestureRecognizerDelegate {
    private static let displayQueue = DispatchQueue(
        label: "io.github.felikslv01.rich-text-view.table-display",
        qos: .userInitiated
    )
    override class var layerClass: AnyClass { RichTableLayer.self }
    private var model: RichTableLayoutModel?
    private var tileTask: RichRenderLayerDisplayTask?
    private var displayGeneration: UInt = 0
    private lazy var attachments = RichAttachmentManager(hostView: self)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        let scale = UIScreen.main.scale
        contentScaleFactor = scale
        layer.contentsScale = scale
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        guard abs(layer.contentsScale - scale) > 0.01 else { return }
        contentScaleFactor = scale
        layer.contentsScale = scale
        if let model { redraw(model, traits: traitCollection) }
    }

    func apply(_ model: RichTableLayoutModel) {
        self.model = model
        accessibilityElements = nil
        let boxes = model.rows.flatMap { row in row.flatMap { cell in
            cell.layout.attachmentRunBoxes.map { box in
                RichAttachmentRunBox(element: box.element,
                    frame: box.frame.offsetBy(dx: cell.frame.minX, dy: cell.frame.minY),
                    contentFrame: box.contentFrame.offsetBy(dx: cell.frame.minX, dy: cell.frame.minY),
                    globalRange: box.globalRange)
            }
        } }
        attachments.apply(boxes)
        redraw(model, traits: traitCollection)
    }

    fileprivate func redraw(_ model: RichTableLayoutModel, traits: UITraitCollection) {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        contentScaleFactor = scale
        layer.contentsScale = scale
        let size = model.contentSize
        guard size.width > 0, size.height > 0 else {
            (layer as? RichTableLayer)?.drawTable = nil
            displayGeneration &+= 1
            layer.contents = nil
            return
        }
        let draw = { (context: CGContext) in
            traits.performAsCurrent { model.draw(in: context) }
        }
        if let tile = layer as? RichTiledLayer {
            let task = RichRenderLayerDisplayTask()
            task.display = { context, size, _ in
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                draw(context)
            }
            tileTask = task
            tile.update(task: task, size: size)
            tile.setNeedsDisplay()
            return
        }
        (layer as? RichTableLayer)?.drawTable = draw
        displayGeneration &+= 1
        let token = displayGeneration
        Self.displayQueue.async { [weak self] in
            let image: CGImage? = autoreleasepool {
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                format.opaque = false
                format.preferredRange = .standard
                return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                    draw(renderer.cgContext)
                }.cgImage
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.displayGeneration == token else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.layer.contentsScale = scale
                self.layer.contents = image
                CATransaction.commit()
            }
        }
    }

    override var accessibilityElements: [Any]? {
        get {
            if let cached = super.accessibilityElements { return cached }
            guard let model else { return nil }
            let elements = model.rows.flatMap { row in row.flatMap { cell in
                cell.layout.accessibilityElements(for: cell.snapshot, in: self, origin: cell.frame.origin,
                    attachmentView: attachments.view(for:)) { [weak self] region in
                        guard let self, self.model?.cell(at: cell.frame.origin)?.layout === cell.layout,
                              enclosingRichTextView != nil else { return false }
                        activate(region, in: cell, trigger: .accessibility)
                        return true
                    }
            } }
            super.accessibilityElements = elements
            return elements
        }
        set { super.accessibilityElements = newValue }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === self && enclosingRichTextView?.currentSelection == nil
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        handleTap(at: gesture.location(in: self))
    }

    func handleTap(at point: CGPoint) {
        guard let host = enclosingRichTextView, host.currentSelection == nil, let model,
              let cell = model.cell(at: point) else { return }
        let local = CGPoint(x: point.x - cell.frame.minX, y: point.y - cell.frame.minY)
        if let region = cell.layout.interactiveRegion(at: local) {
            activate(region, in: cell, trigger: .tap)
        }
    }

    private func activate(_ region: RichInteractiveRegion, in cell: RichTableCellLayout, trigger: RichActionEvent.Trigger) {
        guard let host = enclosingRichTextView else { return }
        let rects = region.rects.map { convert($0.offsetBy(dx: cell.frame.minX, dy: cell.frame.minY), to: host) }
        host.activate(RichActionEvent(action: region.action, elementID: region.elementID, range: region.range,
                                     rects: rects, trigger: trigger), sourceLayout: cell.layout)
    }
}

private extension RichTableLayoutModel {
    // Rightmost boundary at or before the coordinate. The terminal edge is outside the grid.
    func index(at coordinate: CGFloat, edges: [CGFloat]) -> Int {
        var lower = 0
        var upper = edges.count
        while lower < upper {
            let mid = lower + (upper - lower) / 2
            if edges[mid] <= coordinate { lower = mid + 1 } else { upper = mid }
        }
        return lower - 1
    }

    func cell(at point: CGPoint) -> RichTableCellLayout? {
        let row = index(at: point.y, edges: rowEdges)
        let column = index(at: point.x, edges: columnEdges)
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
        return rows[row][column]
    }

    func draw(in context: CGContext) {
        let clip = context.boundingBoxOfClipPath
        let grid = CGRect(origin: .zero, size: contentSize)
        let visible = clip.insetBy(dx: -style.borderWidth, dy: -style.borderWidth).intersection(grid)
        guard !visible.isEmpty else { return }
        let firstRow = max(0, index(at: visible.minY, edges: rowEdges))
        let endRow = min(rows.count, index(at: visible.maxY, edges: rowEdges) + 1)
        let firstCol = max(0, index(at: visible.minX, edges: columnEdges))
        let endCol = min(columnEdges.count - 1, index(at: visible.maxX, edges: columnEdges) + 1)
        context.setFillColor(style.headerBackgroundColor.cgColor)
        for row in firstRow..<endRow where headerRows.contains(row) {
            context.fill(CGRect(x: visible.minX, y: rowEdges[row], width: visible.width, height: rowEdges[row + 1] - rowEdges[row]))
        }
        context.setStrokeColor(style.borderColor.cgColor)
        context.setLineWidth(style.borderWidth)
        for column in firstCol..<endCol where column > 0 {
            context.move(to: CGPoint(x: columnEdges[column], y: visible.minY))
            context.addLine(to: CGPoint(x: columnEdges[column], y: visible.maxY))
        }
        for row in firstRow..<endRow where row > 0 {
            context.move(to: CGPoint(x: visible.minX, y: rowEdges[row]))
            context.addLine(to: CGPoint(x: visible.maxX, y: rowEdges[row]))
        }
        context.strokePath()
        for row in rows[firstRow..<endRow] where firstCol < row.count {
            for cell in row[firstCol..<min(endCol, row.count)] where clip.intersects(cell.frame) {
                context.saveGState()
                context.clip(to: cell.frame)
                context.translateBy(x: cell.frame.minX, y: cell.frame.maxY)
                context.scaleBy(x: 1, y: -1)
                cell.layout.draw(in: context, size: cell.frame.size)
                context.restoreGState()
            }
        }
    }
}
