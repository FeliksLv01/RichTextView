import Foundation

public struct RichElementSnapshot: Sendable {
    public let root: RichContainerElement

    public init(root: RichContainerElement) {
        Self.validateUniqueIDs(in: root)
        self.root = root
    }

    public func element(withID id: String) -> RichElement? {
        Self.element(withID: id, in: root)
    }

    public func applying(_ updates: [RichElementUpdate]) -> RichElementSnapshot {
        var root: RichElement = root
        for update in updates {
            root = Self.apply(update, to: root)
        }
        guard let root = root as? RichContainerElement else {
            preconditionFailure("The root rich element cannot be replaced with a leaf")
        }
        return RichElementSnapshot(root: root)
    }

    private static func validateUniqueIDs(in root: RichElement) {
        #if DEBUG
        var pathsByID: [String: String] = [:]
        func visit(_ element: RichElement, path: String) {
            let elementDescription = "\(path) [\(String(describing: type(of: element)))]"
            if let first = pathsByID[element.id] {
                preconditionFailure(
                    "Duplicate rich element ID: \(element.id), "
                        + "first: \(first), duplicate: \(elementDescription)"
                )
            }
            pathsByID[element.id] = elementDescription
            for (index, child) in element.children.enumerated() {
                visit(child, path: "\(path).\(index)")
            }
        }
        visit(root, path: "root")
        #endif
    }

    private static func element(withID id: String, in element: RichElement) -> RichElement? {
        if element.id == id { return element }
        for child in element.children {
            if let match = self.element(withID: id, in: child) { return match }
        }
        return nil
    }

    private static func apply(_ update: RichElementUpdate, to root: RichElement) -> RichElement {
        switch update {
        case let .update(element):
            let result = replacing(elementID: element.id, with: element, in: root)
            precondition(result.changed, "Rich element not found: \(element.id)")
            return result.element
        case let .replace(id, element):
            let result = replacing(elementID: id, with: element, in: root)
            precondition(result.changed, "Rich element not found: \(id)")
            return result.element
        case let .insert(element, parentID, index):
            let result = inserting(element, parentID: parentID, index: index, in: root)
            precondition(result.changed, "Parent rich element not found: \(parentID)")
            return result.element
        case let .remove(id):
            precondition(id != root.id, "The root rich element cannot be removed")
            let result = removing(elementID: id, from: root)
            precondition(result.changed, "Rich element not found: \(id)")
            return result.element
        }
    }

    private static func replacing(
        elementID: String,
        with replacement: RichElement,
        in current: RichElement
    ) -> (element: RichElement, changed: Bool) {
        if current.id == elementID { return (replacement, true) }
        var changed = false
        let children = current.children.map { child in
            guard !changed else { return child }
            let result = replacing(elementID: elementID, with: replacement, in: child)
            changed = result.changed
            return result.element
        }
        return changed ? (current.replacingChildren(children), true) : (current, false)
    }

    private static func inserting(
        _ inserted: RichElement,
        parentID: String,
        index: Int,
        in current: RichElement
    ) -> (element: RichElement, changed: Bool) {
        if current.id == parentID {
            precondition(current is RichContainerElement, "Only container elements accept insertion")
            var children = current.children
            let insertionIndex = min(max(0, index), children.count)
            children.insert(inserted, at: insertionIndex)
            return (current.replacingChildren(children), true)
        }
        var changed = false
        let children = current.children.map { child in
            guard !changed else { return child }
            let result = inserting(inserted, parentID: parentID, index: index, in: child)
            changed = result.changed
            return result.element
        }
        return changed ? (current.replacingChildren(children), true) : (current, false)
    }

    private static func removing(
        elementID: String,
        from current: RichElement
    ) -> (element: RichElement, changed: Bool) {
        var changed = false
        var children: [RichElement] = []
        for child in current.children {
            if child.id == elementID {
                changed = true
                continue
            }
            if !changed {
                let result = removing(elementID: elementID, from: child)
                children.append(result.element)
                changed = result.changed
            } else {
                children.append(child)
            }
        }
        return changed ? (current.replacingChildren(children), true) : (current, false)
    }
}

public enum RichElementUpdate: Sendable {
    case update(RichElement)
    case replace(id: String, with: RichElement)
    case insert(RichElement, parentID: String, index: Int)
    case remove(id: String)

    fileprivate var targetID: String {
        switch self {
        case let .update(element): element.id
        case let .replace(id, _): id
        case let .insert(element, _, _): element.id
        case let .remove(id): id
        }
    }
}
