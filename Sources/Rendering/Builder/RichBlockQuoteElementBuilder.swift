
public final class RichBlockQuoteElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.blockQuote
    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        let metrics = context.configuration.metrics
        return RichContainerElement(
            id: node.id,
            children: children,
            contentInsets: RichContainerInsets(left: metrics.blockQuoteIndicatorWidth + metrics.blockQuoteContentSpacing),
            decoration: .leadingRule(color: context.configuration.blockQuoteColor, width: metrics.blockQuoteIndicatorWidth)
        )
    }
}
