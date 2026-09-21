import UIKit

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
    public let actionIdentifier: String?

    public init(
        elementID: String,
        range: NSRange,
        globalRange: NSRange,
        copyText: String?,
        actionIdentifier: String?
    ) {
        self.elementID = elementID
        self.range = range
        self.globalRange = globalRange
        self.copyText = copyText
        self.actionIdentifier = actionIdentifier
    }
}

public final class RichTextRunBox: RichRunBox, @unchecked Sendable {
    public let text: NSAttributedString
    let layout: RichCoreTextLayout
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
        self.segments = segments
        self.globalRange = globalRange
        super.init(id: id, frame: frame)
    }

    func actionIdentifier(at point: CGPoint) -> String? {
        segments.reversed().first { segment in
            guard segment.actionIdentifier != nil else { return false }
            return layout.selectionRects(for: segment.range).contains {
                $0.contains(point)
            }
        }?.actionIdentifier
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

extension RichRunBox {
    func hasSameDrawing(as other: RichRunBox) -> Bool {
        guard id == other.id, frame == other.frame else { return false }
        switch (self, other) {
        case let (a as RichTextRunBox, b as RichTextRunBox):
            return a.layout === b.layout
        case let (a as RichDecorationRunBox, b as RichDecorationRunBox):
            switch (a.decoration, b.decoration) {
            case let (.background(ac, ar), .background(bc, br)): return ac == bc && ar == br
            case let (.topRoundedBackground(ac, ar), .topRoundedBackground(bc, br)): return ac == bc && ar == br
            case let (.borderedBackground(ac, ar, abc, abw), .borderedBackground(bc, br, bbc, bbw)):
                return ac == bc && ar == br && abc == bbc && abw == bbw
            case let (.verticalGradient(at, ab), .verticalGradient(bt, bb)): return at == bt && ab == bb
            case let (.leadingRule(ac, aw), .leadingRule(bc, bw)): return ac == bc && aw == bw
            case let (.horizontalRule(ac), .horizontalRule(bc)): return ac == bc
            case let (.listMarker(at, aw), .listMarker(bt, bw)): return at == bt && aw == bw
            default: return false
            }
        case let (a as RichImageRunBox, b as RichImageRunBox):
            return a.element === b.element
        case (is RichAttachmentRunBox, is RichAttachmentRunBox):
            return true // Attachments draw in their own UIViews.
        default: return false
        }
    }
}
