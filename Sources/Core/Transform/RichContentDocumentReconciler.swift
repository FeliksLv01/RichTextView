import Foundation

public enum RichContentDocumentReconciler {
    public static func reconcile(
        _ document: RichContentDocument,
        with previousDocument: RichContentDocument?
    ) -> RichContentDocument {
        guard let previousDocument else { return document }
        return RichContentDocument(root: reconcile(document.root, with: previousDocument.root))
    }

    private static func reconcile(_ node: RichContentNode, with previousNode: RichContentNode?) -> RichContentNode {
        guard let previousNode, previousNode.id == node.id, previousNode.type == node.type else { return node }
        let previousChildren = Dictionary(uniqueKeysWithValues: previousNode.children.map { ($0.id, $0) })
        let children = node.children.map { reconcile($0, with: previousChildren[$0.id]) }
        let layoutChanged = layoutSignature(node) != layoutSignature(previousNode)
            || children.map(\.id) != previousNode.children.map(\.id)
            || zip(children, previousNode.children).contains { $0.revision.layout != $1.revision.layout }
        let displayChanged = displaySignature(node) != displaySignature(previousNode)
            || zip(children, previousNode.children).contains { $0.revision.display != $1.revision.display }
        return RichContentNode(
            id: node.id,
            type: node.type,
            content: node.content,
            children: children,
            revision: RichContentRevision(
                layout: layoutChanged ? increment(previousNode.revision.layout) : previousNode.revision.layout,
                display: displayChanged ? increment(previousNode.revision.display) : previousNode.revision.display
            )
        )
    }

    private static func layoutSignature(_ node: RichContentNode) -> String {
        (node.content as? any RichContentNodeContentSignatureProviding)?.richContentLayoutSignature
            ?? String(reflecting: type(of: node.content))
    }

    private static func displaySignature(_ node: RichContentNode) -> String {
        (node.content as? any RichContentNodeContentSignatureProviding)?.richContentDisplaySignature
            ?? layoutSignature(node)
    }

    private static func increment(_ value: Int) -> Int {
        value == .max ? value : value + 1
    }
}
