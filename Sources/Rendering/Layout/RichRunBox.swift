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
    public let layout: RichCoreTextLayout
    public let segments: [RichTextSegment]
    public let globalRange: NSRange

    public init(
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
    public let textLayout: RichCoreTextLayout?

    public init(
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
