import UIKit

public final class RichTextLayoutEngine: @unchecked Sendable {
    private final class TextCacheKey: NSObject {
        let signature: Int
        let width: CGFloat
        let attributedText: NSAttributedString

        init(signature: Int, width: CGFloat, attributedText: NSAttributedString) {
            self.signature = signature
            self.width = width
            self.attributedText = attributedText
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(signature)
            hasher.combine(width)
            hasher.combine(attributedText.hash)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? TextCacheKey else { return false }
            return signature == other.signature
                && width == other.width
                && attributedText.isEqual(to: other.attributedText)
        }
    }

    private final class CachedTextLayout {
        let text: NSAttributedString
        let layout: RichCoreTextLayout
        let size: CGSize
        let localSegments: [LocalSegment]

        init(
            text: NSAttributedString,
            layout: RichCoreTextLayout,
            size: CGSize,
            localSegments: [LocalSegment]
        ) {
            self.text = text
            self.layout = layout
            self.size = size
            self.localSegments = localSegments
        }
    }

    private struct LocalSegment {
        let elementID: String
        let range: NSRange
        let copyText: String?
        let actionIdentifier: String?
    }

    private struct InlineContent {
        let id: String
        let text: NSAttributedString
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
    private let textCache = NSCache<TextCacheKey, CachedTextLayout>()

    public init(cacheCapacity: Int = 128) {
        let countLimit = max(1, cacheCapacity)
        textCache.countLimit = countLimit
        textCache.totalCostLimit = countLimit > Int.max / Self.estimatedCostPerEntry
            ? Int.max
            : countLimit * Self.estimatedCostPerEntry
    }

    public func layout(
        snapshot: RichElementSnapshot,
        constrainedTo constrainedSize: CGSize
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
        var state = LayoutState(width: width)
        layoutContainer(root, state: &state, isRoot: true)
        state.flushInline(using: self)

        let height = ceil(state.cursorY)
        let result = RichTextLayout(
            rootElementID: snapshot.root.id,
            constrainedSize: constrainedSize,
            contentSize: CGSize(width: ceil(state.maximumWidth), height: height),
            runBoxes: state.runBoxes,
            lines: state.lines
        )
        return result
    }

    public func removeAllCachedLayouts() {
        lock.lock()
        defer { lock.unlock() }
        textCache.removeAllObjects()
    }

    private func layoutContainer(
        _ container: RichContainerElement,
        state: inout LayoutState,
        isRoot: Bool
    ) {
        if container.display == .inline {
            state.appendInline(container, using: self)
            return
        }

        if !isRoot, canFlattenAsInline(container), container.contentInsets == .zero,
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
        case .background:
            let frame = CGRect(x: x, y: startY, width: state.width, height: max(0, endY - startY))
            state.appendDecoration(RichDecorationRunBox(
                id: "\(container.id)-decoration",
                frame: frame,
                decoration: decoration
            ))
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
            let occupied = clampedSize(attachment.metrics.occupiedSize, maximumWidth: state.width)
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

    private func canFlattenAsInline(_ container: RichContainerElement) -> Bool {
        container.children.allSatisfy { child in
            if child is RichTextElement || child is RichTextBadgeElement || child is RichImageElement {
                return true
            }
            if child is RichAttachmentElement {
                return child.display == .inline
            }
            if let nested = child as? RichContainerElement {
                return nested.display == .inline && canFlattenAsInline(nested)
            }
            return false
        }
    }

    private func makeInlineContent(from element: RichElement) -> InlineContent {
        var builder = InlineBuilder()
        builder.append(element)
        return builder.content(id: element.id)
    }

    private func textLayout(for content: InlineContent, width: CGFloat) -> CachedTextLayout? {
        let key = TextCacheKey(
            signature: content.signature,
            width: width,
            attributedText: NSAttributedString(attributedString: content.text)
        )
        if let cached = textCache.object(forKey: key) {
            return cached
        }

        guard let layout = RichCoreTextLayout(
            attributedText: content.text,
            constrainedWidth: width,
            maximumNumberOfLines: content.maximumNumberOfLines,
            lineBreakMode: content.lineBreakMode
        ) else { return nil }
        let size = layout.size
        let cached = CachedTextLayout(
            text: content.text,
            layout: layout,
            size: size,
            localSegments: content.segments
        )
        textCache.setObject(cached, forKey: key, cost: Self.estimatedCost(of: cached))
        return cached
    }

    private static let estimatedCostPerEntry = 16 * 1_024

    private static func estimatedCost(of cached: CachedTextLayout) -> Int {
        4_096
            + cached.text.length * MemoryLayout<unichar>.stride
            + cached.layout.lines.count * 512
            + cached.localSegments.count * 128
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

        mutating func append(_ element: RichElement) {
            hasher.combine(element.id)
            hasher.combine(element.revision.layout)
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
                    actionIdentifier: badge.actionIdentifier.isEmpty ? nil : badge.actionIdentifier
                ))
                hasher.combine(badge.attributedText.richViewFingerprint)
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
                let attributedText = textElement.attributedText
                let range = NSRange(location: text.length, length: attributedText.length)
                text.append(attributedText)
                segments.append(LocalSegment(
                    elementID: textElement.id,
                    range: range,
                    copyText: textElement.copyText,
                    actionIdentifier: (textElement as? RichActionElement)?.actionIdentifier
                ))
                hasher.combine(textElement.attributedText.richViewFingerprint)
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
                    actionIdentifier: imageElement.actionIdentifier.isEmpty
                        ? nil
                        : imageElement.actionIdentifier
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
            InlineContent(
                id: id,
                text: NSAttributedString(attributedString: text),
                segments: segments,
                attachments: attachments,
                signature: hasher.finalize(),
                maximumNumberOfLines: maximumNumberOfLines,
                lineBreakMode: lineBreakMode
            )
        }
    }

    private struct LayoutState {
        var originX: CGFloat = 0
        var width: CGFloat
        var cursorY: CGFloat = 0
        var maximumWidth: CGFloat = 0
        var globalTextLocation = 0
        var runBoxes: [RichRunBox] = []
        var lines: [RichLineBox] = []
        private var inlineElements: [RichElement] = []

        init(width: CGFloat) {
            self.width = width
        }

        mutating func appendInline(_ element: RichElement, using engine: RichTextLayoutEngine) {
            inlineElements.append(element)
        }

        mutating func flushInline(using engine: RichTextLayoutEngine) {
            guard !inlineElements.isEmpty else { return }
            var builder = InlineBuilder()
            inlineElements.forEach { builder.append($0) }
            let id = inlineElements.map(\.id).joined(separator: "+")
            appendTextBlock(builder.content(id: id), spacing: 0, using: engine)
            inlineElements.removeAll(keepingCapacity: true)
        }

        mutating func appendTextBlock(
            _ content: InlineContent,
            spacing: CGFloat,
            using engine: RichTextLayoutEngine
        ) {
            guard content.text.length > 0,
                  let cached = engine.textLayout(for: content, width: width) else { return }
            let frame = CGRect(origin: CGPoint(x: originX, y: cursorY), size: cached.size)
            let textLocation = globalTextLocation
            let globalRange = NSRange(
                location: textLocation,
                length: cached.text.length
            )
            let segments = cached.localSegments.map { segment in
                RichTextSegment(
                    elementID: segment.elementID,
                    range: segment.range,
                    globalRange: NSRange(
                        location: textLocation + segment.range.location,
                        length: segment.range.length
                    ),
                    copyText: segment.copyText,
                    actionIdentifier: segment.actionIdentifier
                )
            }
            let runBox = RichTextRunBox(
                id: content.id,
                frame: frame,
                text: cached.text,
                layout: cached.layout,
                segments: segments,
                globalRange: globalRange
            )
            append(runBox)
            for attachment in content.attachments {
                guard let localFrame = cached.layout.inlineRunRect(
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
            globalTextLocation += cached.text.length + 1
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
