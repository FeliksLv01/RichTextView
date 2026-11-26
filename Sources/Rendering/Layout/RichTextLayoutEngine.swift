import UIKit

public final class RichTextLayoutEngine: @unchecked Sendable {
    public static let shared = RichTextLayoutEngine(cacheCapacity: 128)

    private struct Slot: Hashable {
        let rootID: String
        let id: String
        let widthPx: Int
    }

    private struct CachedTextLayout {
        var text: NSAttributedString { layout.attributedText }
        let layout: RichCoreTextLayout
        var estimatedCost: Int { 4_096 + text.length * 2 + layout.lines.count * 512 }
        let width: CGFloat
        let signature: Int
        let maximumNumberOfLines: Int
        let lineBreakMode: NSLineBreakMode
        var lastAccess: UInt64
    }

    private struct LocalSegment {
        let elementID: String
        let range: NSRange
        let copyText: String?
        let action: RichAction?
    }

    private struct InlineContent {
        let id: String
        let isCacheable: Bool
        let text: NSAttributedString
        let textWithActions: NSAttributedString?
        let segments: [LocalSegment]
        let attachments: [LocalInlineAttachment]
        let signature: Int
        let maximumNumberOfLines: Int
        let lineBreakMode: NSLineBreakMode
    }

    private struct LocalInlineAttachment {
        let element: RichAttachmentElement
        let range: NSRange
    }

    private let lock = NSLock()
    private let cacheCapacity: Int
    private let costLimit: Int
    private let widthScale: CGFloat
    private var cachedCost = 0
    private var slots: [Slot: CachedTextLayout] = [:]
    private var access: UInt64 = 0
    private var cacheObservers: [NSObjectProtocol] = []

    public init(cacheCapacity: Int = 128) {
        self.cacheCapacity = max(1, cacheCapacity)
        let bytesPerEntry = 16 * 1_024
        costLimit = min(self.cacheCapacity, Int.max / bytesPerEntry) * bytesPerEntry
        widthScale = max(1, UITraitCollection.current.displayScale)
        cacheObservers = [UIApplication.didReceiveMemoryWarningNotification, UIApplication.didEnterBackgroundNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.removeAllCachedLayouts()
            }
        }
    }

    deinit {
        cacheObservers.forEach(NotificationCenter.default.removeObserver)
    }

    var cachedLayoutCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return slots.count
    }

    public func layout(
        snapshot: RichElementSnapshot,
        constrainedTo constrainedSize: CGSize
    ) -> RichTextLayout {
        layout(snapshot: snapshot, constrainedTo: constrainedSize, cachesLayouts: true)
    }

    func layout(
        snapshot: RichElementSnapshot,
        constrainedTo constrainedSize: CGSize,
        cachesLayouts: Bool
    ) -> RichTextLayout {
        lock.lock()
        defer { lock.unlock() }
        let width = max(0, constrainedSize.width)
        guard width > 0 else {
            return RichTextLayout(
                rootElementID: snapshot.root.id,
                constrainedSize: constrainedSize,
                contentSize: .zero,
                runBoxes: [],
                lines: []
            )
        }

        let root = snapshot.root
        var state = LayoutState(rootID: root.id, width: width, cachesLayouts: cachesLayouts)
        layoutContainer(root, state: &state, isRoot: true)
        state.flushInline(using: self)

        let height = ceil(state.cursorY)
        let result = RichTextLayout(
            rootElementID: snapshot.root.id,
            constrainedSize: constrainedSize,
            contentSize: CGSize(width: ceil(state.maximumWidth), height: height),
            runBoxes: state.runBoxes,
            lines: state.lines,
            codeBlockTextByID: state.codeBlockTextByID
        )
        return result
    }

    public func removeAllCachedLayouts() {
        lock.lock()
        defer { lock.unlock() }
        slots.removeAll()
        cachedCost = 0
    }

    private func layoutContainer(
        _ container: RichContainerElement,
        state: inout LayoutState,
        isRoot: Bool
    ) {
        if let code = container.codeBlockText {
            state.codeBlockTextByID[container.id] = code
        }
        if container.display == .inline {
            state.appendInline(container, using: self)
            return
        }

        if !isRoot, canFlattenAsInline(container, width: state.width), container.contentInsets == .zero,
           container.decoration == nil {
            state.flushInline(using: self)
            let content = makeInlineContent(from: container)
            state.appendTextBlock(content, spacing: container.spacing, using: self)
            return
        }

        state.flushInline(using: self)
        let originalX = state.originX
        let originalWidth = state.width
        let decorationStartY = state.cursorY
        state.cursorY += max(0, container.contentInsets.top)
        state.originX += max(0, container.contentInsets.left)
        state.width = max(0, state.width - max(0, container.contentInsets.left) - max(0, container.contentInsets.right))

        var appendedBlock = false
        for child in container.children {
            if child.display == .inline {
                if let latex = child as? RichLatexElement, latex.size.width > state.width {
                    state.flushInline(using: self)
                    layoutBlock(latex, state: &state)
                    appendedBlock = true
                    continue
                }
                state.appendInline(child, using: self)
                continue
            }

            state.flushInline(using: self)
            if appendedBlock, container.spacing > 0 {
                state.cursorY += container.spacing
            }
            layoutBlock(child, state: &state)
            appendedBlock = true
        }
        state.flushInline(using: self)
        state.cursorY += max(0, container.contentInsets.bottom)
        let decorationEndY = state.cursorY
        state.originX = originalX
        state.width = originalWidth
        appendDecoration(
            for: container,
            x: originalX,
            startY: decorationStartY,
            endY: decorationEndY,
            state: &state
        )
    }

    private func appendDecoration(
        for container: RichContainerElement,
        x: CGFloat,
        startY: CGFloat,
        endY: CGFloat,
        state: inout LayoutState
    ) {
        guard let decoration = container.decoration else { return }
        switch decoration {
        case .background, .topRoundedBackground, .borderedBackground:
            let frame = CGRect(x: x, y: startY, width: state.width, height: max(0, endY - startY))
            state.appendDecoration(RichDecorationRunBox(
                id: "\(container.id)-decoration",
                frame: frame,
                decoration: decoration
            ))
        case .verticalGradient:
            assertionFailure("Vertical gradients are laid out by RichVerticalGradientElement")
        case let .leadingRule(_, width):
            let frame = CGRect(x: x, y: startY, width: max(0, width), height: max(0, endY - startY))
            state.appendDecoration(RichDecorationRunBox(
                id: "\(container.id)-decoration",
                frame: frame,
                decoration: decoration
            ))
        case let .listMarker(attributedText, width):
            let markerWidth = max(0, width)
            let textLayout = RichCoreTextLayout(
                attributedText: attributedText,
                constrainedWidth: markerWidth
            )
            let markerX = x + max(0, container.contentInsets.left - markerWidth)
            let frame = CGRect(x: markerX, y: startY, width: markerWidth, height: max(1, endY - startY))
            state.appendDecoration(RichDecorationRunBox(
                id: "\(container.id)-decoration",
                frame: frame,
                decoration: decoration,
                textLayout: textLayout
            ))
        case .horizontalRule:
            assertionFailure("Horizontal rules are laid out by RichDividerElement")
        }
    }

    private func layoutBlock(_ element: RichElement, state: inout LayoutState) {
        switch element {
        case let container as RichContainerElement:
            layoutContainer(container, state: &state, isRoot: false)
        case let latex as RichLatexElement:
            let content = makeInlineContent(from: latex.fitting(width: state.width), isCacheable: false)
            state.appendTextBlock(content, spacing: 0, using: self)
        case let text as RichTextElement:
            state.appendTextBlock(makeInlineContent(from: text), spacing: 0, using: self)
        case let image as RichImageElement:
            let size = clampedSize(image.size, maximumWidth: state.width)
            let frame = CGRect(origin: CGPoint(x: state.originX, y: state.cursorY), size: size)
            let globalRange = state.allocateAtomicSelectionRange()
            let runBox = RichImageRunBox(
                element: image,
                frame: frame,
                globalRange: globalRange
            )
            state.append(runBox)
        case let attachment as RichAttachmentElement:
            let occupiedSize = attachment.metrics.occupiedSize
            let occupied = CGSize(
                width: min(max(0, occupiedSize.width), state.width),
                height: max(0, occupiedSize.height)
            )
            let frame = CGRect(origin: CGPoint(x: state.originX, y: state.cursorY), size: occupied)
            let padding = attachment.metrics.padding
            let contentFrame = CGRect(
                x: frame.minX + padding.left,
                y: frame.minY + padding.top,
                width: max(0, min(attachment.metrics.size.width, frame.width - padding.left - padding.right)),
                height: max(0, min(attachment.metrics.size.height, frame.height - padding.top - padding.bottom))
            )
            let globalRange = attachment.isSelectable
                ? state.allocateAtomicSelectionRange()
                : NSRange(location: state.globalTextLocation, length: 0)
            state.append(RichAttachmentRunBox(
                element: attachment,
                frame: frame,
                contentFrame: contentFrame,
                globalRange: globalRange
            ))
        case let gradient as RichVerticalGradientElement:
            let frame = CGRect(
                x: state.originX,
                y: max(0, state.cursorY - gradient.extent),
                width: state.width,
                height: gradient.extent
            )
            state.appendDecoration(RichDecorationRunBox(
                id: gradient.id,
                frame: frame,
                decoration: .verticalGradient(topColor: gradient.topColor, bottomColor: gradient.bottomColor)
            ))
        case let lineBreak as RichBreakElement:
            state.cursorY += max(0, lineBreak.extent)
        case let divider as RichDividerElement:
            let frame = CGRect(
                x: state.originX,
                y: state.cursorY + max(0, (divider.extent - divider.lineHeight) / 2),
                width: state.width,
                height: divider.lineHeight
            )
            state.appendDecoration(RichDecorationRunBox(
                id: divider.id,
                frame: frame,
                decoration: .horizontalRule(color: divider.color)
            ))
            state.cursorY += divider.extent
        default:
            assertionFailure("Unsupported RichElement type: \(type(of: element))")
        }
    }

    private func canFlattenAsInline(_ container: RichContainerElement, width: CGFloat) -> Bool {
        container.children.allSatisfy { child in
            if let latex = child as? RichLatexElement, latex.size.width > width {
                return false
            }
            if child is RichTextElement || child is RichTextBadgeElement || child is RichImageElement {
                return true
            }
            if child is RichAttachmentElement {
                return child.display == .inline
            }
            if let nested = child as? RichContainerElement {
                return nested.display == .inline && canFlattenAsInline(nested, width: width)
            }
            return false
        }
    }

    private func makeInlineContent(from element: RichElement, isCacheable: Bool = true) -> InlineContent {
        var builder = InlineBuilder(isCacheable: isCacheable)
        builder.append(element)
        return builder.content(id: element.id)
    }

    private func textLayout(for content: InlineContent, rootID: String, width: CGFloat, cachesLayouts: Bool) -> RichCoreTextLayout? {
        // The same engine can serve main-thread measurement and background layout.
        // Exact width below also protects wrap boundaries within one pixel slot.
        let key = cachesLayouts ? Slot(rootID: rootID, id: content.id, widthPx: Int((min(width, 100_000) * widthScale).rounded())) : nil
        if let key {
            if content.isCacheable {
                access &+= 1
                if var cached = slots[key], cached.width == width,
                   cached.signature == content.signature,
                   cached.maximumNumberOfLines == content.maximumNumberOfLines,
                   cached.lineBreakMode == content.lineBreakMode,
                   cached.text.isEqual(to: content.text) {
                    cached.lastAccess = access
                    slots[key] = cached
                    return cached.layout
                }
            }
            if let prior = slots.removeValue(forKey: key) { cachedCost -= prior.estimatedCost }
        }

        guard let layout = RichCoreTextLayout(
            attributedText: content.text,
            constrainedWidth: width,
            maximumNumberOfLines: content.maximumNumberOfLines,
            lineBreakMode: content.lineBreakMode
        ) else { return nil }
        guard let key, content.isCacheable else { return layout }
        let cached = CachedTextLayout(
            layout: layout,
            width: width,
            signature: content.signature,
            maximumNumberOfLines: content.maximumNumberOfLines,
            lineBreakMode: content.lineBreakMode,
            lastAccess: access
        )
        guard cached.estimatedCost <= costLimit else { return layout }
        while slots.count >= cacheCapacity || cachedCost > costLimit - cached.estimatedCost {
            guard let oldest = slots.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
            cachedCost -= oldest.value.estimatedCost
            slots.removeValue(forKey: oldest.key)
        }
        slots[key] = cached
        cachedCost += cached.estimatedCost
        return layout
    }

    private func clampedSize(_ size: CGSize, maximumWidth: CGFloat) -> CGSize {
        guard size.width > maximumWidth, size.width > 0 else {
            return CGSize(width: max(0, size.width), height: max(0, size.height))
        }
        let scale = maximumWidth / size.width
        return CGSize(width: maximumWidth, height: max(0, size.height * scale))
    }

    private struct InlineBuilder {
        private var text = NSMutableAttributedString()
        private var segments: [LocalSegment] = []
        private var attachments: [LocalInlineAttachment] = []
        private var hasher = Hasher()
        private var maximumNumberOfLines = 0
        private var lineBreakMode: NSLineBreakMode = .byWordWrapping
        private var isCacheable: Bool

        init(isCacheable: Bool = true) {
            self.isCacheable = isCacheable
        }

        mutating func append(_ element: RichElement) {
            hasher.combine(element.id)
            let action = (element as? RichActionElement)?.action
            switch element {
            case let badge as RichTextBadgeElement:
                let attachment = RichInlineRunFactory.textBadge(
                    attributedText: badge.attributedText,
                    contentInsets: badge.contentInsets,
                    outerInsets: badge.outerInsets,
                    cornerRadius: badge.cornerRadius,
                    borderColor: badge.borderColor,
                    borderWidth: badge.borderWidth,
                    baselineOffset: badge.baselineOffset
                )
                let range = NSRange(location: text.length, length: attachment.length)
                text.append(attachment)
                segments.append(LocalSegment(
                    elementID: badge.id,
                    range: range,
                    copyText: badge.copyText,
                    action: action
                ))
                hasher.combine(badge.attributedText.hash)
                hasher.combine(badge.contentInsets.top)
                hasher.combine(badge.contentInsets.left)
                hasher.combine(badge.contentInsets.bottom)
                hasher.combine(badge.contentInsets.right)
                hasher.combine(badge.outerInsets.top)
                hasher.combine(badge.outerInsets.left)
                hasher.combine(badge.outerInsets.bottom)
                hasher.combine(badge.outerInsets.right)
                hasher.combine(badge.cornerRadius)
                hasher.combine(badge.borderColor?.hash ?? 0)
                hasher.combine(badge.borderWidth)
                hasher.combine(badge.baselineOffset)
            case let textElement as RichTextElement:
                if textElement is RichLatexElement { isCacheable = false }
                let attributedText = textElement.attributedText
                let range = NSRange(location: text.length, length: attributedText.length)
                text.append(attributedText)
                segments.append(LocalSegment(
                    elementID: textElement.id,
                    range: range,
                    copyText: textElement.copyText,
                    action: action
                ))
                hasher.combine(attributedText.length)
                if textElement.maximumNumberOfLines > 0 {
                    maximumNumberOfLines = maximumNumberOfLines == 0
                        ? textElement.maximumNumberOfLines
                        : min(maximumNumberOfLines, textElement.maximumNumberOfLines)
                }
                if textElement.lineBreakMode != .byWordWrapping {
                    lineBreakMode = textElement.lineBreakMode
                }
                hasher.combine(textElement.maximumNumberOfLines)
                hasher.combine(textElement.lineBreakMode.rawValue)
            case let imageElement as RichImageElement:
                if imageElement.source.image != nil { isCacheable = false }
                let attachment = RichInlineRunFactory.image(
                    identifier: imageElement.source.identifier,
                    image: imageElement.source.image,
                    size: imageElement.size,
                    contentInsets: imageElement.contentInsets,
                    font: imageElement.font,
                    contentMode: imageElement.contentMode,
                    tintColor: imageElement.tintColor
                )
                let range = NSRange(location: text.length, length: attachment.length)
                text.append(attachment)
                segments.append(LocalSegment(
                    elementID: imageElement.id,
                    range: range,
                    copyText: imageElement.copyText,
                    action: action
                ))
                hasher.combine(imageElement.source.identifier)
                hasher.combine(imageElement.size.width)
                hasher.combine(imageElement.size.height)
                hasher.combine(imageElement.tintColor?.hash ?? 0)
            case let attachmentElement as RichAttachmentElement:
                let attachment = RichInlineRunFactory.viewAttachment(
                    metrics: attachmentElement.metrics,
                    font: attachmentElement.font
                        ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
                )
                let range = NSRange(
                    location: text.length,
                    length: attachment.length
                )
                text.append(attachment)
                attachments.append(LocalInlineAttachment(
                    element: attachmentElement,
                    range: range
                ))
                let metrics = attachmentElement.metrics
                hasher.combine(metrics.size.width)
                hasher.combine(metrics.size.height)
                hasher.combine(metrics.padding.top)
                hasher.combine(metrics.padding.left)
                hasher.combine(metrics.padding.bottom)
                hasher.combine(metrics.padding.right)
            case let container as RichContainerElement:
                container.children.forEach { append($0) }
            default:
                assertionFailure("Only inline text and image elements may be flattened")
            }
        }

        mutating func content(id: String) -> InlineContent {
            for segment in segments {
                hasher.combine(segment.range)
                hasher.combine(segment.copyText)
                hasher.combine(segment.action)
            }
            // Action-only edits reuse Core Text geometry. Keep the original attributes on the run box.
            let range = NSRange(location: 0, length: text.length)
            var drawingText: NSMutableAttributedString?
            text.enumerateAttribute(.richAction, in: range, options: .longestEffectiveRangeNotRequired) { value, _, stop in
                guard value != nil else { return }
                let copy = NSMutableAttributedString(attributedString: text)
                copy.removeAttribute(.richAction, range: range)
                drawingText = copy
                stop.pointee = true
            }
            return InlineContent(
                id: id,
                isCacheable: isCacheable,
                // The builder is finished. Only a cache miss needs an immutable copy,
                // which RichCoreTextLayout takes before the text escapes into the cache.
                text: drawingText ?? text,
                textWithActions: drawingText == nil ? nil : NSAttributedString(attributedString: text),
                segments: segments,
                attachments: attachments,
                signature: hasher.finalize(),
                maximumNumberOfLines: maximumNumberOfLines,
                lineBreakMode: lineBreakMode
            )
        }
    }

    private struct LayoutState {
        let rootID: String
        let cachesLayouts: Bool
        var originX: CGFloat = 0
        var width: CGFloat
        var cursorY: CGFloat = 0
        var maximumWidth: CGFloat = 0
        var codeBlockTextByID: [String: String] = [:]
        var globalTextLocation = 0
        var runBoxes: [RichRunBox] = []
        var lines: [RichLineBox] = []
        private var inlineElements: [RichElement] = []

        init(rootID: String, width: CGFloat, cachesLayouts: Bool) {
            self.rootID = rootID
            self.width = width
            self.cachesLayouts = cachesLayouts
        }

        mutating func appendInline(_ element: RichElement, using engine: RichTextLayoutEngine) {
            inlineElements.append(element)
        }

        mutating func flushInline(using engine: RichTextLayoutEngine) {
            guard let first = inlineElements.first else { return }
            var builder = InlineBuilder()
            inlineElements.forEach { builder.append($0) }
            appendTextBlock(builder.content(id: first.id), spacing: 0, using: engine)
            inlineElements.removeAll(keepingCapacity: true)
        }

        mutating func appendTextBlock(
            _ content: InlineContent,
            spacing: CGFloat,
            using engine: RichTextLayoutEngine
        ) {
            guard content.text.length > 0,
                  let layout = engine.textLayout(for: content, rootID: rootID, width: width, cachesLayouts: cachesLayouts) else { return }
            let frame = CGRect(origin: CGPoint(x: originX, y: cursorY), size: layout.size)
            let textLocation = globalTextLocation
            let globalRange = NSRange(
                location: textLocation,
                length: layout.attributedText.length
            )
            let segments = content.segments.map { segment in
                RichTextSegment(
                    elementID: segment.elementID,
                    range: segment.range,
                    globalRange: NSRange(
                        location: textLocation + segment.range.location,
                        length: segment.range.length
                    ),
                    copyText: segment.copyText,
                    action: segment.action
                )
            }
            let runBox = RichTextRunBox(
                id: content.id,
                frame: frame,
                text: content.textWithActions ?? layout.attributedText,
                layout: layout,
                segments: segments,
                globalRange: globalRange
            )
            append(runBox)
            for attachment in content.attachments {
                guard let localFrame = layout.inlineRunRect(
                    at: attachment.range.location
                ) else { continue }
                let attachmentFrame = localFrame.offsetBy(
                    dx: frame.minX,
                    dy: frame.minY
                )
                let padding = attachment.element.metrics.padding
                let contentFrame = attachmentFrame.inset(by: padding)
                let attachmentGlobalRange = attachment.element.isSelectable
                    ? NSRange(
                        location: textLocation + attachment.range.location,
                        length: attachment.range.length
                    )
                    : NSRange(
                        location: textLocation + attachment.range.location,
                        length: 0
                    )
                appendOverlay(RichAttachmentRunBox(
                    element: attachment.element,
                    frame: attachmentFrame,
                    contentFrame: contentFrame,
                    globalRange: attachmentGlobalRange
                ))
            }
            globalTextLocation += layout.attributedText.length + 1
            if spacing > 0 { cursorY += spacing }
        }

        mutating func append(_ runBox: RichRunBox) {
            runBoxes.append(runBox)
            lines.append(RichLineBox(frame: runBox.frame, runBoxIDs: [runBox.id]))
            cursorY = runBox.frame.maxY
            maximumWidth = max(maximumWidth, runBox.frame.maxX)
        }

        mutating func appendDecoration(_ runBox: RichDecorationRunBox) {
            runBoxes.append(runBox)
            maximumWidth = max(maximumWidth, runBox.frame.maxX)
        }

        mutating func appendOverlay(_ runBox: RichRunBox) {
            runBoxes.append(runBox)
            maximumWidth = max(maximumWidth, runBox.frame.maxX)
        }

        mutating func allocateAtomicSelectionRange() -> NSRange {
            let range = NSRange(location: globalTextLocation, length: 1)
            globalTextLocation += 2
            return range
        }
    }
}
