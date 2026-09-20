
public protocol RichContentElementBuilding {
    /// Immutable extra inputs beyond the node and render context; include every external value read by build.
    associatedtype Inputs: Hashable
    var inputs: Inputs { get }
    var nodeType: RichContentNodeType { get }

    func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement?
}
