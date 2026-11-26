import UIKit

enum RichSelectionState: Equatable {
    case idle
    case selected(RichSemanticRange)
    case longPressing(anchor: RichSemanticRange, current: RichSemanticRange)
    case dragging(handle: RichSelectionHandleKind, anchor: RichSemanticPosition, current: RichSemanticRange)

    var current: RichSemanticRange? {
        switch self {
        case .idle: nil
        case let .selected(range), let .longPressing(_, range), let .dragging(_, _, range): range
        }
    }

    mutating func beginDrag(_ handle: RichSelectionHandleKind) {
        guard case let .selected(range) = self else { return }
        self = .dragging(handle: handle, anchor: handle == .start ? range.end : range.start, current: range)
    }

    mutating func extend(to range: RichSemanticRange) {
        switch self {
        case let .longPressing(anchor, _): self = .longPressing(anchor: anchor, current: range)
        case let .dragging(handle, anchor, _): self = .dragging(handle: handle, anchor: anchor, current: range)
        default: break
        }
    }

    mutating func finish() {
        if let current { self = .selected(current) }
    }
}

@MainActor
final class RichSelectionController: NSObject, UIGestureRecognizerDelegate {
    var isEnabled: Bool {
        get { longPressGesture.isEnabled }
        set {
            longPressGesture.isEnabled = newValue
            if !newValue { clearSelection() }
        }
    }

    private weak var hostView: RichTextView?
    private var layout: RichTextLayout?
    private(set) var state = RichSelectionState.idle
    private weak var selectionWindow: UIWindow?
    private var highlightView: RichSelectionHighlightView?
    private var handleOverlay: RichSelectionHandleOverlay?
    private var boundaries: (start: CGRect, end: CGRect)?
    private var displayLink: CADisplayLink?
    private var dragWindowPoint: CGPoint?
    private var loupeSession: RichTextLoupeSession?
    private lazy var selectionFeedback = UISelectionFeedbackGenerator()
    private let competingGestures = NSHashTable<UIGestureRecognizer>.weakObjects()
    private lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        gesture.minimumPressDuration = 0.35
        gesture.delegate = self
        return gesture
    }()

    private static let autoScrollEdgeInset: CGFloat = 64
    private static let autoScrollMinimumSpeed: CGFloat = 2
    private static let autoScrollMaximumSpeed: CGFloat = 16

    init(hostView: RichTextView) {
        self.hostView = hostView
        super.init()
        longPressGesture.isEnabled = hostView.isTextSelectionEnabled
        hostView.addGestureRecognizer(longPressGesture)
        if let layout = hostView.currentLayout { apply(layout: layout) }
    }

    func prioritizeSelection(over gesture: UIGestureRecognizer) {
        competingGestures.add(gesture)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === longPressGesture && competingGestures.contains(otherGestureRecognizer)
    }

    func apply(layout: RichTextLayout?) {
        let previousRoot = self.layout?.rootElementID
        self.layout = layout
        guard state != .idle else { return }
        guard let layout, previousRoot == layout.rootElementID, let current = state.current,
              let range = globalRange(for: current) else {
            clearSelection()
            return
        }
        switch state {
        case let .longPressing(anchor, _) where globalRange(for: anchor) == nil:
            clearSelection()
        case let .dragging(_, anchor, _) where globalPosition(for: anchor) == nil:
            clearSelection()
        default:
            updateOverlay(for: range)
        }
    }

    func clearSelection() {
        guard state != .idle else { return }
        state = .idle
        removeSelectionViews()
        if let hostView {
            hostView.selectionMenuPresenter?.dismissCopyMenu(from: hostView)
            hostView.notifySelectionChanged(nil)
        }
    }

    func removeSelectionViews() {
        displayLink?.invalidate()
        displayLink = nil
        endTracking()
        highlightView?.removeFromSuperview()
        highlightView = nil
        handleOverlay?.removeFromSuperview()
        handleOverlay = nil
        boundaries = nil
        if let selectionWindow { RichSelectionWindowCoordinator.release(selectionWindow, for: self) }
        selectionWindow = nil
    }

    func didMoveToWindow() {
        if selectionWindow !== hostView?.window { clearSelection() }
    }

    func updateAppearance() {
        highlightView?.updateAppearance()
        handleOverlay?.tintColor = hostView?.tintColor
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === longPressGesture, let hostView else { return false }
        return initialSelectionRange(at: gestureRecognizer.location(in: hostView), policy: hostView.initialSelectionPolicy) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === hostView
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let hostView else { return }
        let point = gesture.location(in: hostView)
        switch gesture.state {
        case .began: beginLongPress(at: point)
        case .changed: extendSelection(to: point)
        case .ended, .cancelled, .failed:
            if case .longPressing = state { finishInteraction() }
        default: break
        }
    }

    func beginLongPress(at point: CGPoint) {
        guard isEnabled, let hostView, let window = hostView.window,
              let range = initialSelectionRange(at: point, policy: hostView.initialSelectionPolicy),
              let anchor = semanticRange(for: range) else { return }
        selectionFeedback.prepare()
        endTracking()
        state = .longPressing(anchor: anchor, current: anchor)
        selectionWindow = window
        RichSelectionWindowCoordinator.claim(window, for: self)
        guard case .longPressing = state else { return }
        updateOverlay(for: range)
        guard case .longPressing = state else { return }
        selectionFeedback.selectionChanged()
        beginLoupeSession(at: point, in: hostView)
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
            guard let hit = layout?.textHit(at: point),
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
            guard let hit = layout?.textHit(at: point),
                  let localRange = hit.runBox.layout.paragraphRange(at: hit.localPoint)
                      ?? hit.runBox.layout.lineRange(at: hit.localPoint) else {
                return nil
            }
            return NSRange(
                location: hit.runBox.globalRange.location + localRange.location,
                length: localRange.length
            )
        case .word:
            guard let hit = layout?.textHit(at: point),
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

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let handle = gesture.view as? RichSelectionHandleView, let hostView else { return }
        let point = gesture.location(in: hostView)
        if gesture.state == .began {
            beginHandleDrag(handle.kind, at: point)
            return
        }
        guard case let .dragging(active, _, _) = state, active == handle.kind else { return }
        switch gesture.state {
        case .changed: extendSelection(to: point)
        case .ended:
            extendSelection(to: point)
            finishInteraction()
        case .cancelled, .failed: finishInteraction()
        default: break
        }
    }

    func beginHandleDrag(_ handle: RichSelectionHandleKind, at point: CGPoint) {
        guard case .selected = state, let hostView else { return }
        state.beginDrag(handle)
        hostView.selectionMenuPresenter?.dismissCopyMenu(from: hostView)
        guard case .dragging = state else { return }
        beginLoupeSession(at: point, in: hostView)
    }

    func extendSelection(to point: CGPoint) {
        guard let hostView, let window = selectionWindow, let position = closestGlobalPosition(at: point) else { return }
        let range: NSRange?
        switch state {
        case let .longPressing(anchor, _):
            guard let initial = globalRange(for: anchor) else { return }
            let lower = min(initial.location, position)
            let upper = max(NSMaxRange(initial), position)
            range = normalizedSelectionRange(between: lower, and: upper)
        case let .dragging(_, anchor, _):
            guard let fixed = globalPosition(for: anchor) else { return }
            range = normalizedSelectionRange(between: fixed, and: position)
        default: return
        }
        dragWindowPoint = hostView.convert(point, to: window)
        if let range, let current = semanticRange(for: range), state.current != current {
            state.extend(to: current)
            updateOverlay(for: range)
        }
        loupeSession?.move(to: point)
    }

    func finishInteraction() {
        guard let current = state.current, let range = globalRange(for: current) else { return }
        let menuHandle: RichSelectionHandleKind?
        switch state {
        case let .dragging(_, anchor, _):
            menuHandle = globalPosition(for: anchor) == range.location ? .end : .start
        case let .longPressing(anchor, _):
            if anchor.start != current.start { menuHandle = .start }
            else if anchor.end != current.end { menuHandle = .end }
            else { menuHandle = nil }
        default: return
        }
        state.finish()
        endTracking()
        updateOverlay(for: range, showMenu: true, menuHandle: menuHandle)
    }

    private func endTracking() {
        dragWindowPoint = nil
        loupeSession?.invalidate()
        loupeSession = nil
    }

    func isSelectionHandleTouch(atWindowPoint point: CGPoint) -> Bool {
        guard let handleOverlay, let window = selectionWindow else { return false }
        return handleOverlay.hitTest(handleOverlay.convert(point, from: window), with: nil) != nil
    }

    private func updateOverlay(for range: NSRange, showMenu: Bool = false, menuHandle: RichSelectionHandleKind? = nil) {
        guard let hostView, let window = selectionWindow else { return }
        let rects = selectionRects(for: range)
        guard let fallbackFirst = rects.first, let fallbackLast = rects.last else {
            clearSelection()
            return
        }
        let first = boundaryRect(at: range.location, takingLast: false) ?? fallbackFirst
        let last = boundaryRect(at: NSMaxRange(range) - 1, takingLast: true) ?? fallbackLast
        boundaries = (first, last)
        if highlightView == nil {
            let highlight = RichSelectionHighlightView(frame: hostView.bounds)
            hostView.addSubview(highlight)
            highlightView = highlight
            let overlay = RichSelectionHandleOverlay(target: self, action: #selector(handlePan(_:)))
            overlay.tintColor = hostView.tintColor
            window.addSubview(overlay)
            handleOverlay = overlay
            let link = CADisplayLink(target: self, selector: #selector(displayTick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        if let highlightView {
            hostView.bringSubviewToFront(highlightView)
            highlightView.update(rects: rects)
        }
        syncHandles(in: enclosingScrollView())
        let selection = selection(for: range)
        hostView.notifySelectionChanged(selection)
        if showMenu, let selection, state == .selected(selection.semanticRange) {
            let sourceRect: CGRect
            switch menuHandle {
            case .start: sourceRect = first
            case .end: sourceRect = last
            case nil: sourceRect = rects.reduce(first) { $0.union($1) }
            }
            hostView.presentCopyMenu(sourceRect: sourceRect, selection: selection)
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
        guard let semanticRange = state.current else { return nil }
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
              normalizedUpper > normalizedLower else { return nil }
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

    @objc private func displayTick() {
        guard let hostView, let window = selectionWindow else {
            clearSelection()
            return
        }
        let scrollView = enclosingScrollView()
        if let scrollView, let dragWindowPoint {
            let offset = autoScrollOffset(in: scrollView, windowPoint: dragWindowPoint)
            if offset != scrollView.contentOffset.y {
                scrollView.contentOffset.y = offset
                extendSelection(to: hostView.convert(dragWindowPoint, from: window))
            }
        }
        syncHandles(in: scrollView)
    }

    private func syncHandles(in scrollView: UIScrollView?) {
        guard let window = selectionWindow, let hostView, let handleOverlay, let boundaries else { return }
        var visible = window.bounds
        if let scrollView {
            visible = visible.intersection(scrollView.convert(scrollView.bounds.inset(by: scrollView.safeAreaInsets), to: window))
            var ancestor = scrollView.superview
            while let view = ancestor, view !== window {
                if view.clipsToBounds { visible = visible.intersection(view.convert(view.bounds, to: window)) }
                ancestor = view.superview
            }
        }
        let frame = visible.isNull ? .zero : visible
        if handleOverlay.frame != frame { handleOverlay.frame = frame }
        handleOverlay.position(start: hostView.convert(boundaries.start, to: handleOverlay),
                               end: hostView.convert(boundaries.end, to: handleOverlay))
    }

    private func autoScrollOffset(
        in scrollView: UIScrollView,
        windowPoint: CGPoint
    ) -> CGFloat {
        let inset = scrollView.adjustedContentInset
        let pointInScroll = scrollView.convert(windowPoint, from: selectionWindow)
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
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled {
                let insets = scroll.adjustedContentInset
                if scroll.alwaysBounceVertical || scroll.contentSize.height + insets.top + insets.bottom > scroll.bounds.height {
                    return scroll
                }
            }
            candidate = view.superview
        }
        return nil
    }

    private func beginLoupeSession(at point: CGPoint, in hostView: UIView) {
        guard #available(iOS 17.0, *), let window = hostView.window, !window.isHidden else { return }
        loupeSession = UITextLoupeSession.begin(at: point, fromSelectionWidgetView: nil, in: hostView)
        loupeSession?.move(to: point)
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
