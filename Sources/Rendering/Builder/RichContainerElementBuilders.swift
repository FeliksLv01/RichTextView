
public final class RichRootElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.root
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children, spacing: context.configuration.metrics.blockSpacing)
    }
}

public final class RichParagraphElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.paragraph
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children)
    }
}

public final class RichInlineElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.inline
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(
            id: node.id,
            children: children,
            display: .inline
        )
    }
}

public final class RichHeadingElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.heading
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children)
    }
}

public final class RichCodeBlockElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.codeBlock
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children)
    }
}

public final class RichDividerElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.divider
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichDividerElement(
            id: node.id,
            color: context.configuration.dividerColor,
            lineHeight: context.configuration.dividerHeight,
            extent: context.configuration.dividerExtent,
            revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
        )
    }
}

public final class RichColumnsElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.columns
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children, spacing: context.configuration.metrics.blockSpacing)
    }
}

public final class RichColumnElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.column
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children, spacing: context.configuration.metrics.blockSpacing)
    }
}

public final class RichReferenceElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.reference
    public init() {}
    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        RichContainerElement(id: node.id, children: children, spacing: context.configuration.metrics.blockSpacing)
    }
}
