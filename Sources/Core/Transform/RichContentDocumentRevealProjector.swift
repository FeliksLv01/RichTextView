import Foundation

public struct RichContentRevealResult: Sendable {
    public let document: RichContentDocument
    public let visibleUnitCount: Int
    public let totalUnitCount: Int

    public init(document: RichContentDocument, visibleUnitCount: Int, totalUnitCount: Int) {
        self.document = document
        self.visibleUnitCount = visibleUnitCount
        self.totalUnitCount = totalUnitCount
    }
}

public struct RichContentDocumentRevealProjector {
    public struct Configuration: Sendable {
        public let entryUnitNodeTypes: Set<RichContentNodeType>
        public let unmeteredSubtreeNodeTypes: Set<RichContentNodeType>

        public init(
            entryUnitNodeTypes: Set<RichContentNodeType> = [],
            unmeteredSubtreeNodeTypes: Set<RichContentNodeType> = []
        ) {
            self.entryUnitNodeTypes = entryUnitNodeTypes
            self.unmeteredSubtreeNodeTypes = unmeteredSubtreeNodeTypes
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func project(
        _ document: RichContentDocument,
        visibleUnitCount: Int,
        previousProjection: RichContentDocument? = nil
    ) -> RichContentRevealResult {
        let total = unitCount(in: document.root)
        var remaining = max(0, min(visibleUnitCount, total))
        let projectedRoot = project(document.root, remaining: &remaining, keepsEmptyContainer: true)
            ?? RichContentNode(id: document.root.id, type: .root)
        let projected = RichContentDocument(root: projectedRoot)
        return RichContentRevealResult(
            document: projected,
            visibleUnitCount: max(0, min(visibleUnitCount, total)),
            totalUnitCount: total
        )
    }

    public func unitCount(in document: RichContentDocument) -> Int {
        unitCount(in: document.root)
    }

    private func unitCount(in node: RichContentNode) -> Int {
        if configuration.unmeteredSubtreeNodeTypes.contains(node.type) {
            return 0
        }
        let entryUnit = configuration.entryUnitNodeTypes.contains(node.type) ? 1 : 0
        if let text = node.content(as: RichTextContent.self) {
            return entryUnit + text.text.count
        }
        if node.children.isEmpty, node.type != .root {
            return max(1, entryUnit)
        }
        return entryUnit + node.children.reduce(0) { $0 + unitCount(in: $1) }
    }

    private func project(
        _ node: RichContentNode,
        remaining: inout Int,
        keepsEmptyContainer: Bool = false
    ) -> RichContentNode? {
        if configuration.unmeteredSubtreeNodeTypes.contains(node.type) {
            return node
        }
        let consumesEntryUnit = configuration.entryUnitNodeTypes.contains(node.type)
        if consumesEntryUnit {
            guard remaining > 0 else { return nil }
            remaining -= 1
        }
        if let text = node.content(as: RichTextContent.self) {
            guard remaining > 0 else { return nil }
            let visibleCount = min(remaining, text.text.count)
            remaining -= visibleCount
            return RichContentNode(
                id: node.id,
                type: node.type,
                content: RichTextContent(text: String(text.text.prefix(visibleCount)), style: text.style)
            )
        }
        if node.children.isEmpty {
            if consumesEntryUnit { return node }
            guard remaining > 0 else { return nil }
            remaining -= 1
            return node
        }
        var children: [RichContentNode] = []
        for child in node.children {
            guard remaining > 0
                    || configuration.unmeteredSubtreeNodeTypes.contains(child.type) else { break }
            if let projectedChild = project(child, remaining: &remaining) {
                children.append(projectedChild)
            }
        }
        guard keepsEmptyContainer || !children.isEmpty else { return nil }
        return RichContentNode(
            id: node.id,
            type: node.type,
            content: node.content,
            children: children
        )
    }
}
