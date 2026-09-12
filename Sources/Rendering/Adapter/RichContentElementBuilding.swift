
public protocol RichContentElementBuilding {
    var nodeType: RichContentNodeType { get }

    func build(
        node: RichContentNode,
        children: [RichElement],
        context: RichContentRenderContext
    ) -> RichElement?
}
