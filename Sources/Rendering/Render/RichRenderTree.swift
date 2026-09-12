import UIKit

public struct RichRenderDirtyState: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let layout = RichRenderDirtyState(rawValue: 1 << 0)
    public static let display = RichRenderDirtyState(rawValue: 1 << 1)
    public static let children = RichRenderDirtyState(rawValue: 1 << 2)
    public static let all: RichRenderDirtyState = [.layout, .display, .children]
}

open class RichRenderObject: @unchecked Sendable {
    public let id: String
    public private(set) var element: RichElement
    public private(set) weak var parent: RichRenderObject?
    public private(set) var children: [RichRenderObject] = []
    public private(set) var dirtyState: RichRenderDirtyState = .all

    fileprivate var layoutFingerprint: Int
    fileprivate var displayFingerprint: Int

    fileprivate init(element: RichElement) {
        id = element.id
        self.element = element
        layoutFingerprint = Self.makeLayoutFingerprint(element)
        displayFingerprint = Self.makeDisplayFingerprint(element)
    }

    public func markClean() {
        dirtyState = []
        children.forEach { $0.markClean() }
    }

    fileprivate func reconcile(with newElement: RichElement) {
        let newLayoutFingerprint = Self.makeLayoutFingerprint(newElement)
        let newDisplayFingerprint = Self.makeDisplayFingerprint(newElement)
        if layoutFingerprint != newLayoutFingerprint { dirtyState.insert(.layout) }
        if displayFingerprint != newDisplayFingerprint { dirtyState.insert(.display) }
        element = newElement
        layoutFingerprint = newLayoutFingerprint
        displayFingerprint = newDisplayFingerprint

        var existingByID = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) })
        let reconciledChildren = newElement.children.map { childElement -> RichRenderObject in
            if let existing = existingByID.removeValue(forKey: childElement.id),
               type(of: existing.element) == type(of: childElement) {
                existing.reconcile(with: childElement)
                return existing
            }
            dirtyState.insert(.children)
            return RichRenderObject.make(element: childElement)
        }
        if !existingByID.isEmpty || reconciledChildren.map(\.id) != children.map(\.id) {
            dirtyState.insert(.children)
        }
        children = reconciledChildren
        children.forEach { $0.parent = self }
    }

    fileprivate static func make(element: RichElement) -> RichRenderObject {
        let object: RichRenderObject
        switch element {
        case is RichContainerElement: object = RichRenderContainer(element: element)
        case is RichTextBadgeElement: object = RichRenderText(element: element)
        case is RichTextElement: object = RichRenderText(element: element)
        case is RichImageElement: object = RichRenderImage(element: element)
        case is RichAttachmentElement: object = RichRenderAttachment(element: element)
        default: object = RichRenderObject(element: element)
        }
        object.children = element.children.map(make)
        object.children.forEach { $0.parent = object }
        return object
    }

    private static func makeLayoutFingerprint(_ element: RichElement) -> Int {
        var hasher = Hasher()
        hasher.combine(element.id)
        hasher.combine(ObjectIdentifier(type(of: element)))
        hasher.combine(element.revision.layout)
        hasher.combine(element.display == .block)
        switch element {
        case let container as RichContainerElement:
            hasher.combine(container.spacing)
            hasher.combine(container.contentInsets)
            hasher.combine(container.children.map(\.id))
        case let badge as RichTextBadgeElement:
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
            hasher.combine(badge.baselineOffset)
            hasher.combine(badge.actionIdentifier)
        case let text as RichTextElement:
            hasher.combine(text.attributedText.richViewFingerprint)
            hasher.combine(text.maximumNumberOfLines)
            hasher.combine(text.lineBreakMode.rawValue)
        case let image as RichImageElement:
            hasher.combine(image.size.width)
            hasher.combine(image.size.height)
            hasher.combine(image.contentInsets.top)
            hasher.combine(image.contentInsets.left)
            hasher.combine(image.contentInsets.bottom)
            hasher.combine(image.contentInsets.right)
            hasher.combine(image.font.pointSize)
        case let attachment as RichAttachmentElement:
            hasher.combine(attachment.metrics.occupiedSize.width)
            hasher.combine(attachment.metrics.occupiedSize.height)
            hasher.combine(attachment.reuseIdentifier)
        case let lineBreak as RichBreakElement:
            hasher.combine(lineBreak.extent)
        default:
            break
        }
        return hasher.finalize()
    }

    private static func makeDisplayFingerprint(_ element: RichElement) -> Int {
        var hasher = Hasher()
        hasher.combine(element.revision.display)
        switch element {
        case let badge as RichTextBadgeElement:
            hasher.combine(badge.attributedText.richViewFingerprint)
        case let text as RichTextElement: hasher.combine(text.attributedText.richViewFingerprint)
        case let image as RichImageElement:
            hasher.combine(image.source.identifier)
            hasher.combine(image.tintColor?.hash ?? 0)
        case let attachment as RichAttachmentElement:
            hasher.combine(ObjectIdentifier(attachment.provider))
        default: break
        }
        return hasher.finalize()
    }
}

public final class RichRenderContainer: RichRenderObject, @unchecked Sendable {}
public final class RichRenderText: RichRenderObject, @unchecked Sendable {}
public final class RichRenderImage: RichRenderObject, @unchecked Sendable {}
public final class RichRenderAttachment: RichRenderObject, @unchecked Sendable {}

public final class RichRenderTree: @unchecked Sendable {
    public private(set) var root: RichRenderObject

    public init(snapshot: RichElementSnapshot) {
        root = RichRenderObject.make(element: snapshot.root)
    }

    @discardableResult
    public func reconcile(snapshot: RichElementSnapshot) -> RichRenderObject {
        guard root.id == snapshot.root.id,
              type(of: root.element) == type(of: snapshot.root) else {
            root = RichRenderObject.make(element: snapshot.root)
            return root
        }
        root.reconcile(with: snapshot.root)
        return root
    }

    public func markClean() {
        root.markClean()
    }
}
