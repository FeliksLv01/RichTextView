import UIKit

@MainActor
final class RichSelectionController: NSObject, UIGestureRecognizerDelegate {
    var isEnabled = true {
        didSet {
            longPressGesture.isEnabled = isEnabled
            if !isEnabled { clearSelection() }
        }
    }

    private weak var hostView: RichTextView?
    private var layout: RichTextLayout?
    private var selectedGlobalRange: NSRange?
    private var selectedSemanticRange: RichSemanticRange?
    private var activeCursor: RichSelectionCursor?
    private var dragAnchorPosition: Int?
    private var loupeSession: RichTextLoupeSession?
    private var prioritizedScrollViewIDs = Set<ObjectIdentifier>()
    private var touchCancellationSuspendedScrollViews: [(scrollView: UIScrollView, previous: Bool)] = []
    private var lastDraggedHandleIsStart: Bool?
    private var longPressAnchorRange: NSRange?
    private var autoScrollLink: CADisplayLink?
    private weak var autoScrollScrollView: UIScrollView?
    private var autoScrollWindowPoint: CGPoint?
    private lazy var selectionFeedback = UISelectionFeedbackGenerator()

    private static let autoScrollEdgeInset: CGFloat = 64
    private static let autoScrollMinimumSpeed: CGFloat = 2
    private static let autoScrollMaximumSpeed: CGFloat = 16

    private lazy var overlayView: RichSelectionOverlayView = {
        let view = RichSelectionOverlayView(frame: .zero)
        view.isHidden = true
        return view
    }()

    private lazy var longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var handlePanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleHandlePan(_:))
        )
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = self
        // NOTE: 默认 true 会在 begin 时给 hostView 补发 touchesCancelled，经 cancelHandleDrag
        // 清空 activeCursor，后续 .changed 全被 moveHandleDrag 挡掉，表现为选区只挪一行就卡死。
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    init(hostView: RichTextView) {
        self.hostView = hostView
        super.init()
        overlayView.frame = hostView.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostView.addSubview(overlayView)
        longPressGesture.minimumPressDuration = 0.35
        longPressGesture.delegate = self
        tapGesture.delegate = self
        hostView.addGestureRecognizer(longPressGesture)
        hostView.addGestureRecognizer(tapGesture)
    }

    var selectionLongPressGestureRecognizer: UILongPressGestureRecognizer {
        longPressGesture
    }

    func apply(layout: RichTextLayout) {
        self.layout = layout
        guard let selectedSemanticRange,
              let rebasedRange = globalRange(for: selectedSemanticRange) else {
            clearSelection()
            return
        }
        selectedGlobalRange = rebasedRange
        updateOverlay()
    }

    func clearSelection() {
        selectedGlobalRange = nil
        selectedSemanticRange = nil
        activeCursor = nil
        dragAnchorPosition = nil
        lastDraggedHandleIsStart = nil
        longPressAnchorRange = nil
        stopAutoScroll()
        invalidateLoupeSession()
        overlayView.update(rects: [], startHandleRect: nil, endHandleRect: nil)
        overlayView.isHidden = true
        handlePanGesture.view?.removeGestureRecognizer(handlePanGesture)
        // NOTE: 手势从 window 摘除后，祖先 scrollView 上的 require(toFail:) 随之失效，
        // 必须清掉去重集合，否则下次选中会跳过重建，滚动重新抢走手柄拖拽。
        prioritizedScrollViewIDs.removeAll()
        restoreAncestorTouchCancellation()
        if let hostView {
            hostView.selectionMenuPresenter?.dismissCopyMenu(from: hostView)
            hostView.notifySelectionChanged(nil)
        }
    }

    func updateAppearance() {
        overlayView.updateAppearance()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // handlePanGesture 装在 window 上、只在贴近选区游标时才 begin（见 gestureRecognizerShouldBegin），
        // 允许它与外层列表的滚动手势共存，避免选中态下把全局 pan 全部吃掉导致外层列表拖不动。
        gestureRecognizer === handlePanGesture || otherGestureRecognizer === handlePanGesture
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === tapGesture,
              let hostView,
              let otherView = otherGestureRecognizer.view,
              otherView !== hostView else { return false }
        return otherView.isDescendant(of: hostView)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === handlePanGesture {
            guard selectedGlobalRange != nil, let hostView else { return false }
            return isNearSelectionHandle(
                gestureRecognizer.location(in: hostView)
            )
        }
        guard selectedGlobalRange != nil,
              let hostView,
              gestureRecognizer === tapGesture || gestureRecognizer === longPressGesture else {
            return true
        }
        return !isNearSelectionHandle(gestureRecognizer.location(in: hostView))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // handlePanGesture 装在 window 上，其入口已由 gestureRecognizerShouldBegin 的
        // isNearSelectionHandle 把关，这里放行所有 touch，避免 touch 落在 hostView 子视图
        // （attachment / image 等）上时被误拒，导致第二次拖拽 handle 拖不动。
        if gestureRecognizer === handlePanGesture { return true }
        guard let hostView, let touchedView = touch.view else { return true }
        return touchedView === hostView || !touchedView.isDescendant(of: hostView)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard isEnabled, let hostView else { return }
        let point = gesture.location(in: hostView)
        switch gesture.state {
        case .began:
            selectionFeedback.prepare()
            guard let initialRange = initialSelectionRange(
                at: point,
                policy: hostView.initialSelectionPolicy
            ) else { return }
            longPressAnchorRange = initialRange
            lastDraggedHandleIsStart = nil
            updateSelection(initialRange)
            selectionFeedback.selectionChanged()
            updateOverlay(showMenu: false)
            beginLoupeSession(at: point, in: hostView)
        case .changed:
            extendLongPressSelection(to: point)
        case .ended, .cancelled, .failed:
            guard longPressAnchorRange != nil else { return }
            longPressAnchorRange = nil
            stopAutoScroll()
            invalidateLoupeSession()
            guard selectedGlobalRange != nil else { return }
            updateOverlay(showMenu: true)
        default:
            break
        }
    }

    // 长按不松手继续滑动：以初始选区为锚向两侧扩展，滑回锚内则还原为初始选区。
    private func extendLongPressSelection(to point: CGPoint) {
        guard let anchor = longPressAnchorRange else { return }
        updateAutoScroll(for: point)
        guard let position = closestGlobalPosition(at: point) else { return }
        let range: NSRange?
        if position <= anchor.location {
            range = normalizedSelectionRange(between: NSMaxRange(anchor), and: position)
            lastDraggedHandleIsStart = true
        } else if position >= NSMaxRange(anchor) {
            range = normalizedSelectionRange(between: anchor.location, and: position)
            lastDraggedHandleIsStart = false
        } else {
            range = anchor
        }
        guard let range else { return }
        if updateSelection(range) {
            updateOverlay(showMenu: false)
        }
        moveLoupeSession(to: point)
    }

    private func initialSelectionRange(
        at point: CGPoint,
        policy: RichInitialSelectionPolicy
    ) -> NSRange? {
        switch policy {
        case .allContent:
            guard selectableHit(at: point) else { return nil }
            return selectableGlobalRange
        case .currentLine:
            guard let hit = textHit(at: point),
                  let localRange = hit.runBox.layout.lineRange(at: hit.localPoint) else {
                return nil
            }
            return NSRange(
                location: hit.runBox.globalRange.location + localRange.location,
                length: localRange.length
            )
        case .paragraph:
            if let range = layout?.listItemSelectionRange(at: point) {
                return range
            }
            guard let hit = textHit(at: point),
                  let localRange = hit.runBox.layout.paragraphRange(at: hit.localPoint)
                      ?? hit.runBox.layout.lineRange(at: hit.localPoint) else {
                return nil
            }
            return NSRange(
                location: hit.runBox.globalRange.location + localRange.location,
                length: localRange.length
            )
        case .word:
            guard let hit = textHit(at: point),
                  let localRange = hit.runBox.layout.wordRange(at: hit.localPoint)
                      ?? hit.runBox.layout.lineRange(at: hit.localPoint) else {
                return nil
            }
            return NSRange(
                location: hit.runBox.globalRange.location + localRange.location,
                length: localRange.length
            )
        }
    }

    func beginHandleDrag(at point: CGPoint) -> Bool {
        guard isEnabled, let hostView, let selectedGlobalRange,
              let cursor = overlayView.cursor(at: point) else { return false }
        activeCursor = cursor
        lastDraggedHandleIsStart = cursor.kind == .start
        dragAnchorPosition = cursor.kind == .start
            ? NSMaxRange(selectedGlobalRange)
            : selectedGlobalRange.location
        hostView.selectionMenuPresenter?.dismissCopyMenu(from: hostView)
        beginLoupeSession(at: point, in: hostView)
        return true
    }

    func shouldRouteHandleTouch(at point: CGPoint) -> Bool {
        // 不再以 handlePanGesture 是否已安装为前置条件：即使 window 级手势已安装，
        // 也保留 hostView 自身的 touch routing 作为兜底，防止手势被外层拦截后 handle 拖不动。
        isEnabled
            && selectedGlobalRange != nil
            && isNearSelectionHandle(point)
    }

    func isTouchingSelectionHandle(at point: CGPoint) -> Bool {
        isEnabled && selectedGlobalRange != nil && isNearSelectionHandle(point)
    }

    @objc private func handleHandlePan(_ gesture: UIPanGestureRecognizer) {
        guard let hostView else { return }
        let point = gesture.location(in: hostView)
        switch gesture.state {
        case .began:
            _ = beginHandleDrag(at: point)
        case .changed:
            moveHandleDrag(to: point, finished: false)
        case .ended:
            endHandleDrag(at: point, shouldUpdate: true)
        case .cancelled, .failed:
            cancelHandleDrag()
        default:
            break
        }
    }

    func moveHandleDrag(to point: CGPoint, finished: Bool) {
        guard activeCursor != nil else { return }
        if finished {
            stopAutoScroll()
        } else {
            updateAutoScroll(for: point)
        }
        guard let position = closestGlobalPosition(at: point),
              let dragAnchorPosition,
              let range = normalizedSelectionRange(
                  between: dragAnchorPosition,
                  and: position
              ) else { return }
        let changed = updateSelection(range)
        if changed || finished {
            updateOverlay(showMenu: finished)
        }
        if finished {
            activeCursor = nil
            self.dragAnchorPosition = nil
            invalidateLoupeSession()
        } else {
            moveLoupeSession(to: point)
        }
    }

    func endHandleDrag(at point: CGPoint, shouldUpdate: Bool) {
        if shouldUpdate {
            moveHandleDrag(to: point, finished: false)
        }
        activeCursor = nil
        dragAnchorPosition = nil
        stopAutoScroll()
        invalidateLoupeSession()
        updateOverlay(showMenu: true)
    }

    func cancelHandleDrag() {
        activeCursor = nil
        dragAnchorPosition = nil
        stopAutoScroll()
        invalidateLoupeSession()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let hostView else { return }
        let point = gesture.location(in: hostView)
        if selectedGlobalRange != nil, isNearSelectionHandle(point) {
            return
        }
        if selectedGlobalRange != nil {
            clearSelection()
            return
        }
        guard let hit = textHit(at: point) else {
            hostView.notifyUnconsumedTap()
            return
        }
        if let actionIdentifier = hit.runBox.actionIdentifier(at: hit.localPoint) {
            hostView.activate(actionIdentifier)
        } else {
            hostView.notifyUnconsumedTap()
        }
    }

    private func updateOverlay(showMenu: Bool = false) {
        guard let hostView, let selectedGlobalRange else { return }
        let rects = selectionRects(for: selectedGlobalRange)
        guard let fallbackFirst = rects.first, let fallbackLast = rects.last else {
            clearSelection()
            return
        }
        let first = boundaryRect(at: selectedGlobalRange.location, takingLast: false) ?? fallbackFirst
        let last = boundaryRect(at: NSMaxRange(selectedGlobalRange) - 1, takingLast: true) ?? fallbackLast
        overlayView.isHidden = false
        hostView.bringSubviewToFront(overlayView)
        installHandlePanGestureIfNeeded()
        overlayView.update(
            rects: rects,
            startHandleRect: first,
            endHandleRect: last
        )
        let selection = selection(for: selectedGlobalRange)
        hostView.notifySelectionChanged(selection)
        if showMenu, let selection {
            // 菜单跟随最后调整的那个手柄；长按初次选中时没有拖过手柄，仍按整段选区居中。
            let sourceRect: CGRect
            switch lastDraggedHandleIsStart {
            case .some(true):
                sourceRect = first
            case .some(false):
                sourceRect = last
            case .none:
                sourceRect = rects.reduce(first) { $0.union($1) }
            }
            hostView.presentCopyMenu(
                sourceRect: sourceRect,
                selection: selection
            )
        }
    }

    // NOTE: inline attachment 的 run box 以 overlay 形式后置，runBoxes 数组序不等于阅读序。
    private func boundaryRect(at position: Int, takingLast: Bool) -> CGRect? {
        guard position >= 0 else { return nil }
        let rects = selectionRects(for: NSRange(location: position, length: 1))
        return takingLast ? rects.last : rects.first
    }

    private func selectionRects(for globalRange: NSRange) -> [CGRect] {
        guard let layout else { return [] }
        return layout.runBoxes.flatMap { runBox -> [CGRect] in
            if let textRunBox = runBox as? RichTextRunBox {
                let intersection = NSIntersectionRange(globalRange, textRunBox.globalRange)
                guard intersection.length > 0 else { return [] }
                let localRange = NSRange(
                    location: intersection.location - textRunBox.globalRange.location,
                    length: intersection.length
                )
                return textRunBox.layout.selectionRects(for: localRange).map { rect in
                    rect.offsetBy(dx: textRunBox.frame.minX, dy: textRunBox.frame.minY)
                }
            }
            if let imageRunBox = runBox as? RichImageRunBox,
               NSIntersectionRange(globalRange, imageRunBox.globalRange).length > 0 {
                return [imageRunBox.frame]
            }
            if let attachmentRunBox = runBox as? RichAttachmentRunBox,
               NSIntersectionRange(globalRange, attachmentRunBox.globalRange).length > 0 {
                return [attachmentRunBox.contentFrame]
            }
            return []
        }
    }

    private func copyText(for globalRange: NSRange) -> String {
        guard let layout else { return "" }
        return layout.runBoxes.compactMap { runBox -> String? in
            if let textRunBox = runBox as? RichTextRunBox {
                let intersection = NSIntersectionRange(globalRange, textRunBox.globalRange)
                guard intersection.length > 0 else { return nil }
                let selectedLocalRange = NSRange(
                    location: intersection.location - textRunBox.globalRange.location,
                    length: intersection.length
                )
                return textRunBox.segments.compactMap { segment -> String? in
                    let selectedSegmentRange = NSIntersectionRange(selectedLocalRange, segment.range)
                    guard selectedSegmentRange.length > 0 else { return nil }
                    if selectedSegmentRange == segment.range, let copyText = segment.copyText {
                        return copyText
                    }
                    return (textRunBox.text.string as NSString).substring(with: selectedSegmentRange)
                }.joined()
            }
            if let imageRunBox = runBox as? RichImageRunBox,
               NSIntersectionRange(globalRange, imageRunBox.globalRange).length > 0 {
                return imageRunBox.element.copyText
            }
            if let attachmentRunBox = runBox as? RichAttachmentRunBox,
               NSIntersectionRange(globalRange, attachmentRunBox.globalRange).length > 0 {
                return attachmentRunBox.element.copyText
            }
            return nil
        }.joined(separator: "\n")
    }

    private func selection(for globalRange: NSRange) -> RichSelection? {
        guard let semanticRange = semanticRange(for: globalRange) else { return nil }
        return RichSelection(
            globalRange: globalRange,
            semanticRange: semanticRange,
            fragments: selectionFragments(for: globalRange),
            plainText: copyText(for: globalRange)
        )
    }

    private func selectionFragments(for globalRange: NSRange) -> [RichSelectionFragment] {
        guard let layout else { return [] }
        var fragments = layout.textRunBoxes.flatMap { runBox in
            runBox.segments.compactMap { segment -> RichSelectionFragment? in
                let intersection = NSIntersectionRange(globalRange, segment.globalRange)
                guard intersection.length > 0 else { return nil }
                let elementRange = NSRange(
                    location: intersection.location - segment.globalRange.location,
                    length: intersection.length
                )
                let localRange = NSRange(
                    location: intersection.location - runBox.globalRange.location,
                    length: intersection.length
                )
                let plainText = intersection == segment.globalRange
                    ? segment.copyText ?? (runBox.text.string as NSString).substring(with: localRange)
                    : (runBox.text.string as NSString).substring(with: localRange)
                return RichSelectionFragment(
                    elementID: segment.elementID,
                    kind: fragmentKind(for: segment.elementID),
                    utf16Range: elementRange,
                    globalRange: intersection,
                    plainText: plainText
                )
            }
        }
        fragments.append(contentsOf: layout.imageRunBoxes.compactMap { runBox in
            selectionFragment(
                elementID: runBox.element.id,
                kind: .image,
                elementRange: runBox.globalRange,
                selectedRange: globalRange,
                plainText: runBox.element.copyText
            )
        })
        fragments.append(contentsOf: layout.attachmentRunBoxes.compactMap { runBox in
            selectionFragment(
                elementID: runBox.element.id,
                kind: .attachment,
                elementRange: runBox.globalRange,
                selectedRange: globalRange,
                plainText: runBox.element.copyText
            )
        })
        return fragments.sorted {
            if $0.globalRange.location == $1.globalRange.location {
                return $0.kind.sortOrder < $1.kind.sortOrder
            }
            return $0.globalRange.location < $1.globalRange.location
        }
    }

    private func fragmentKind(for elementID: String) -> RichSelectionFragmentKind {
        guard let element = hostView?.currentSnapshot?.element(withID: elementID) else {
            return .text
        }
        if element is RichImageElement { return .image }
        if element is RichAttachmentElement { return .attachment }
        return .text
    }

    private func selectionFragment(
        elementID: String,
        kind: RichSelectionFragmentKind,
        elementRange: NSRange,
        selectedRange: NSRange,
        plainText: String?
    ) -> RichSelectionFragment? {
        let intersection = NSIntersectionRange(selectedRange, elementRange)
        guard intersection.length > 0 else { return nil }
        return RichSelectionFragment(
            elementID: elementID,
            kind: kind,
            utf16Range: NSRange(
                location: intersection.location - elementRange.location,
                length: intersection.length
            ),
            globalRange: intersection,
            plainText: plainText ?? ""
        )
    }

    private func semanticRange(for globalRange: NSRange) -> RichSemanticRange? {
        guard let start = semanticPosition(at: globalRange.location),
              let end = semanticPosition(at: max(globalRange.location, NSMaxRange(globalRange) - 1), trailing: true) else {
            return nil
        }
        return RichSemanticRange(start: start, end: end)
    }

    private func globalRange(for semanticRange: RichSemanticRange) -> NSRange? {
        guard let start = globalPosition(for: semanticRange.start),
              let end = globalPosition(for: semanticRange.end),
              end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func globalPosition(for semanticPosition: RichSemanticPosition) -> Int? {
        guard let layout else { return nil }
        for runBox in layout.textRunBoxes {
            guard let segment = runBox.segments.first(where: { $0.elementID == semanticPosition.elementID }),
                  semanticPosition.utf16Offset <= segment.range.length else { continue }
            return runBox.globalRange.location + segment.range.location + semanticPosition.utf16Offset
        }
        if let runBox = layout.imageRunBoxes.first(where: { $0.element.id == semanticPosition.elementID }),
           semanticPosition.utf16Offset <= runBox.globalRange.length {
            return runBox.globalRange.location + semanticPosition.utf16Offset
        }
        if let runBox = layout.attachmentRunBoxes.first(where: { $0.element.id == semanticPosition.elementID }),
           semanticPosition.utf16Offset <= runBox.globalRange.length {
            return runBox.globalRange.location + semanticPosition.utf16Offset
        }
        return nil
    }

    @discardableResult
    private func updateSelection(_ globalRange: NSRange) -> Bool {
        guard selectedGlobalRange.map({ !NSEqualRanges($0, globalRange) }) ?? true else { return false }
        selectedGlobalRange = globalRange
        selectedSemanticRange = semanticRange(for: globalRange)
        return true
    }

    private func semanticPosition(at globalOffset: Int, trailing: Bool = false) -> RichSemanticPosition? {
        guard let layout else { return nil }
        for runBox in layout.textRunBoxes {
            guard NSLocationInRange(globalOffset, runBox.globalRange) else { continue }
            let localOffset = globalOffset - runBox.globalRange.location
            if let segment = runBox.segments.first(where: { NSLocationInRange(localOffset, $0.range) }) {
                return RichSemanticPosition(
                    elementID: segment.elementID,
                    utf16Offset: localOffset - segment.range.location + (trailing ? 1 : 0)
                )
            }
        }
        if let runBox = layout.imageRunBoxes.first(where: { NSLocationInRange(globalOffset, $0.globalRange) }) {
            return RichSemanticPosition(
                elementID: runBox.element.id,
                utf16Offset: trailing ? 1 : 0
            )
        }
        if let runBox = layout.attachmentRunBoxes.first(where: { NSLocationInRange(globalOffset, $0.globalRange) }) {
            return RichSemanticPosition(
                elementID: runBox.element.id,
                utf16Offset: trailing ? 1 : 0
            )
        }
        return nil
    }

    private var selectableGlobalRange: NSRange? {
        guard let ranges = selectableRanges,
              let lower = ranges.map(\.location).min(),
              let upper = ranges.map(NSMaxRange).max(),
              upper > lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    private func normalizedSelectionRange(between first: Int, and second: Int) -> NSRange? {
        guard let selectableRanges else { return nil }
        let lower = min(first, second)
        let upper = max(first, second)
        let proposed = NSRange(location: lower, length: max(1, upper - lower))
        let intersections = selectableRanges.compactMap { range -> NSRange? in
            let intersection = NSIntersectionRange(proposed, range)
            return intersection.length > 0 ? intersection : nil
        }
        guard let normalizedLower = intersections.map(\.location).min(),
              let normalizedUpper = intersections.map(NSMaxRange).max(),
              normalizedUpper > normalizedLower else { return selectedGlobalRange }
        return NSRange(location: normalizedLower, length: normalizedUpper - normalizedLower)
    }

    private func closestGlobalPosition(at point: CGPoint) -> Int? {
        guard let runBoxes = layout?.runBoxes.filter({ selectableRange(for: $0)?.length == 1 || $0 is RichTextRunBox }),
              !runBoxes.isEmpty else { return nil }
        let runBox = runBoxes.min {
            distanceSquared(from: point, to: $0.frame) < distanceSquared(from: point, to: $1.frame)
        }
        guard let runBox else { return nil }
        if let range = selectableRange(for: runBox), !(runBox is RichTextRunBox) {
            return point.y < runBox.frame.midY ? range.location : NSMaxRange(range)
        }
        guard let textRunBox = runBox as? RichTextRunBox else { return nil }
        let localPoint = CGPoint(
            x: min(max(0, point.x - textRunBox.frame.minX), textRunBox.frame.width),
            y: min(max(0, point.y - textRunBox.frame.minY), textRunBox.frame.height)
        )
        guard let position = textRunBox.layout.closestPosition(to: localPoint) else { return nil }
        return textRunBox.globalRange.location + position
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private func textHit(at point: CGPoint) -> (runBox: RichTextRunBox, localPoint: CGPoint)? {
        guard let runBox = layout?.textRunBoxes.first(where: { $0.frame.insetBy(dx: -12, dy: -8).contains(point) }) else {
            return nil
        }
        return (runBox, CGPoint(x: point.x - runBox.frame.minX, y: point.y - runBox.frame.minY))
    }

    private var selectableRanges: [NSRange]? {
        layout?.runBoxes.compactMap(selectableRange(for:))
    }

    private func selectableRange(for runBox: RichRunBox) -> NSRange? {
        if let textRunBox = runBox as? RichTextRunBox, textRunBox.globalRange.length > 0 {
            return textRunBox.globalRange
        }
        if let imageRunBox = runBox as? RichImageRunBox, imageRunBox.globalRange.length > 0 {
            return imageRunBox.globalRange
        }
        if let attachmentRunBox = runBox as? RichAttachmentRunBox, attachmentRunBox.globalRange.length > 0 {
            return attachmentRunBox.globalRange
        }
        return nil
    }

    private func selectableHit(at point: CGPoint) -> Bool {
        guard let layout else { return false }
        return layout.runBoxes.contains { runBox in
            guard selectableRange(for: runBox) != nil else { return false }
            let frame = (runBox as? RichAttachmentRunBox)?.contentFrame ?? runBox.frame
            return frame.insetBy(dx: -12, dy: -8).contains(point)
        }
    }

    private func isNearSelectionHandle(_ point: CGPoint) -> Bool {
        overlayView.cursor(at: point) != nil
    }

    private func installHandlePanGestureIfNeeded() {
        guard let window = hostView?.window,
              handlePanGesture.view !== window else { return }
        handlePanGesture.view?.removeGestureRecognizer(handlePanGesture)
        window.addGestureRecognizer(handlePanGesture)
        prioritizeHandlePanOverAncestorScrolling()
    }

    private func prioritizeHandlePanOverAncestorScrolling() {
        var candidate = hostView?.superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                let identifier = ObjectIdentifier(scrollView)
                if prioritizedScrollViewIDs.insert(identifier).inserted {
                    scrollView.panGestureRecognizer.require(
                        toFail: handlePanGesture
                    )
                    suspendTouchCancellation(on: scrollView)
                }
            }
            candidate = view.superview
        }
    }

    // NOTE: 手柄拖拽还有一条不依赖手势仲裁的原始触摸通路（RichTextView.touchesBegan → beginHandleDrag），
    // 但 scrollView 默认会在自身滚动起手时取消子视图触摸，把这条通路掐断，表现为「有时拖不动」。
    // 选中期间挂起取消行为，选区清除后原样恢复。
    private func suspendTouchCancellation(on scrollView: UIScrollView) {
        touchCancellationSuspendedScrollViews.append(
            (scrollView, scrollView.canCancelContentTouches)
        )
        scrollView.canCancelContentTouches = false
    }

    private func restoreAncestorTouchCancellation() {
        for entry in touchCancellationSuspendedScrollViews {
            entry.scrollView.canCancelContentTouches = entry.previous
        }
        touchCancellationSuspendedScrollViews.removeAll()
    }

    private func updateAutoScroll(for point: CGPoint) {
        guard let hostView, let scrollView = enclosingScrollView() else {
            stopAutoScroll()
            return
        }
        autoScrollScrollView = scrollView
        autoScrollWindowPoint = hostView.convert(point, to: nil)
        guard autoScrollLink == nil else { return }
        let link = CADisplayLink(
            target: self,
            selector: #selector(handleAutoScrollTick)
        )
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
    }

    private func stopAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
        autoScrollScrollView = nil
        autoScrollWindowPoint = nil
    }

    @objc private func handleAutoScrollTick() {
        // 两条拖拽通路的终止路径都会清各自锚；此处兜底自停，避免 CADisplayLink 持有 self 泄漏。
        guard activeCursor != nil || longPressAnchorRange != nil,
              let hostView,
              let scrollView = autoScrollScrollView,
              let windowPoint = autoScrollWindowPoint else {
            stopAutoScroll()
            return
        }
        let offsetY = autoScrollOffset(in: scrollView, windowPoint: windowPoint)
        guard offsetY != scrollView.contentOffset.y else { return }
        scrollView.contentOffset.y = offsetY
        let hostPoint = hostView.convert(windowPoint, from: nil)
        if activeCursor != nil {
            moveHandleDrag(to: hostPoint, finished: false)
        } else {
            extendLongPressSelection(to: hostPoint)
        }
    }

    private func autoScrollOffset(
        in scrollView: UIScrollView,
        windowPoint: CGPoint
    ) -> CGFloat {
        let inset = scrollView.adjustedContentInset
        let pointInScroll = scrollView.convert(windowPoint, from: nil)
        let trigger = Self.autoScrollEdgeInset
        let topEdge = scrollView.contentOffset.y + inset.top
        let bottomEdge = scrollView.contentOffset.y
            + scrollView.bounds.height
            - inset.bottom
        var delta: CGFloat = 0
        if pointInScroll.y < topEdge + trigger {
            delta = -autoScrollSpeed(forOvershoot: topEdge + trigger - pointInScroll.y)
        } else if pointInScroll.y > bottomEdge - trigger {
            delta = autoScrollSpeed(forOvershoot: pointInScroll.y - bottomEdge + trigger)
        }
        guard delta != 0 else { return scrollView.contentOffset.y }
        let minimumOffset = -inset.top
        let maximumOffset = max(
            minimumOffset,
            scrollView.contentSize.height + inset.bottom - scrollView.bounds.height
        )
        return min(max(scrollView.contentOffset.y + delta, minimumOffset), maximumOffset)
    }

    private func autoScrollSpeed(forOvershoot overshoot: CGFloat) -> CGFloat {
        let ratio = min(1, max(0, overshoot) / Self.autoScrollEdgeInset)
        return Self.autoScrollMinimumSpeed
            + (Self.autoScrollMaximumSpeed - Self.autoScrollMinimumSpeed) * ratio
    }

    private func enclosingScrollView() -> UIScrollView? {
        var candidate = hostView?.superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView { return scrollView }
            candidate = view.superview
        }
        return nil
    }

    private func beginLoupeSession(at point: CGPoint, in hostView: UIView) {
        guard #available(iOS 17.0, *) else { return }
        let session = RichTextLoupeSession()
        session.begin(at: point, in: hostView)
        loupeSession = session
    }

    private func moveLoupeSession(to point: CGPoint) {
        loupeSession?.move(to: point)
    }

    private func invalidateLoupeSession() {
        loupeSession?.invalidate()
        loupeSession = nil
    }
}

private extension RichSelectionFragmentKind {
    var sortOrder: Int {
        switch self {
        case .text: 0
        case .image: 1
        case .attachment: 2
        }
    }
}
