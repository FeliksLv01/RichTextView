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


    fileprivate init(element: RichElement) {
        id = element.id
        self.element = element
    }

    public func markClean() {
        dirtyState = []
        children.forEach { $0.markClean() }
    }

    fileprivate func reconcile(with newElement: RichElement) {
        guard element !== newElement else { return }
        // Built-in rendering reuses equal elements. Rebuilt/custom elements are conservatively dirty.
        dirtyState.formUnion(.all)
        element = newElement

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
