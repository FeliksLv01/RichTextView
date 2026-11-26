import UIKit

public struct RichInteractiveRegion: Hashable, Sendable {
    public let action: RichAction
    public let elementID: String
    /// UTF-16 range in the layout that owns this region.
    public let range: NSRange
    public let rects: [CGRect]

    func contains(_ point: CGPoint) -> Bool {
        rects.contains { $0.contains(point) }
    }

    func event(trigger: RichActionEvent.Trigger) -> RichActionEvent {
        RichActionEvent(action: action, elementID: elementID, range: range, rects: rects, trigger: trigger)
    }
}

extension RichAction {
    static func from(attributes: [NSAttributedString.Key: Any]) -> RichAction? {
        if let action = attributes[.richAction] as? RichAction { return action }
        if let url = attributes[.link] as? URL { return RichAction(.link(url)) }
        if let string = attributes[.link] as? String, let url = URL(string: string) { return RichAction(.link(url)) }
        return nil
    }
}

open class RichRunBox: @unchecked Sendable {
    public let id: String
    public let frame: CGRect

    public init(id: String, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public struct RichTextSegment: Sendable {
    public let elementID: String
    public let range: NSRange
    public let globalRange: NSRange
    public let copyText: String?
    public let action: RichAction?
    public var actionIdentifier: String? { action?.legacyIdentifier }

    public init(
        elementID: String,
        range: NSRange,
        globalRange: NSRange,
        copyText: String?,
        actionIdentifier: String?
    ) {
        self.init(
            elementID: elementID,
            range: range,
            globalRange: globalRange,
            copyText: copyText,
            action: actionIdentifier.flatMap(RichAction.init(legacyIdentifier:))
        )
    }

    public init(
        elementID: String,
        range: NSRange,
        globalRange: NSRange,
        copyText: String?,
        action: RichAction?
    ) {
        self.elementID = elementID
        self.range = range
        self.globalRange = globalRange
        self.copyText = copyText
        self.action = action
    }
}

public final class RichTextRunBox: RichRunBox, @unchecked Sendable {
    public let text: NSAttributedString
    let layout: RichCoreTextLayout
    let interactiveRegions: [RichInteractiveRegion]
    public let segments: [RichTextSegment]
    public let globalRange: NSRange

    init(
        id: String,
        frame: CGRect,
        text: NSAttributedString,
        layout: RichCoreTextLayout,
        segments: [RichTextSegment],
        globalRange: NSRange
    ) {
        self.text = text
        self.layout = layout
        interactiveRegions = segments.flatMap { segment in
            segment.actionRanges(in: text).compactMap { action, range in
                let rects = layout.interactiveRects(for: range).map {
                    $0.offsetBy(dx: frame.minX, dy: frame.minY)
                }
                guard !rects.isEmpty else { return nil }
                return RichInteractiveRegion(
                    action: action,
                    elementID: segment.elementID,
                    range: NSRange(location: globalRange.location + range.location, length: range.length),
                    rects: rects
                )
            }
        }
        self.segments = segments
        self.globalRange = globalRange
        super.init(id: id, frame: frame)
    }

    func actionIdentifier(at point: CGPoint) -> String? {
        let viewPoint = CGPoint(x: point.x + frame.minX, y: point.y + frame.minY)
        return interactiveRegions.last { $0.contains(viewPoint) }?.action.legacyIdentifier
    }
}

private extension RichTextSegment {
    func actionRanges(in text: NSAttributedString) -> [(RichAction, NSRange)] {
        if let action { return [(action, range)] }
        var result: [(RichAction, NSRange)] = []
        text.enumerateAttributes(in: range, options: .longestEffectiveRangeNotRequired) { attributes, subrange, _ in
            guard let action = RichAction.from(attributes: attributes) else { return }
            if let last = result.last, last.0 == action, NSMaxRange(last.1) == subrange.location {
                result[result.count - 1].1.length += subrange.length
            } else {
                result.append((action, subrange))
            }
        }
        return result
    }
}

public final class RichImageRunBox: RichRunBox, @unchecked Sendable {
    public let element: RichImageElement
    public let globalRange: NSRange

    public init(element: RichImageElement, frame: CGRect, globalRange: NSRange = NSRange(location: 0, length: 0)) {
        self.element = element
        self.globalRange = globalRange
        super.init(id: element.id, frame: frame)
    }
}

public final class RichAttachmentRunBox: RichRunBox, @unchecked Sendable {
    public let element: RichAttachmentElement
    public let contentFrame: CGRect
    public let globalRange: NSRange

    public init(
        element: RichAttachmentElement,
        frame: CGRect,
        contentFrame: CGRect,
        globalRange: NSRange = NSRange(location: 0, length: 0)
    ) {
        self.element = element
        self.contentFrame = contentFrame
        self.globalRange = globalRange
        super.init(id: element.id, frame: frame)
    }
}

public final class RichDecorationRunBox: RichRunBox, @unchecked Sendable {
    public let decoration: RichContainerDecoration
    let textLayout: RichCoreTextLayout?

    init(
        id: String,
        frame: CGRect,
        decoration: RichContainerDecoration,
        textLayout: RichCoreTextLayout? = nil
    ) {
        self.decoration = decoration
        self.textLayout = textLayout
        super.init(id: id, frame: frame)
    }
}
