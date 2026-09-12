
import CoreGraphics

public struct RichContentRenderResult: Sendable {
    public let snapshot: RichElementSnapshot
    public let unhandledNodeTypes: Set<RichContentNodeType>

    public init(snapshot: RichElementSnapshot, unhandledNodeTypes: Set<RichContentNodeType>) {
        self.snapshot = snapshot
        self.unhandledNodeTypes = unhandledNodeTypes
    }
}

public struct RichContentRenderer {
    private let registry: RichContentElementBuilderRegistry

    public init(registry: RichContentElementBuilderRegistry = .standard) {
        self.registry = registry
    }

    public func render(
        document: RichContentDocument,
        constrainedWidth: CGFloat,
        configuration: RichContentRenderingConfiguration,
        resolver: (any RichContentPresentationResolving)? = nil
    ) -> RichContentRenderResult {
        var unhandledNodeTypes: Set<RichContentNodeType> = []
        let context = RichContentRenderContext(
            constrainedWidth: constrainedWidth,
            configuration: configuration,
            resolver: resolver
        )
        let root = build(node: document.root, context: context, unhandledNodeTypes: &unhandledNodeTypes)
            as? RichContainerElement ?? RichContainerElement(id: document.root.id, children: [])
        let visibleRoot = RichContainerElement(
            id: root.id,
            children: configuration.leadingElements + root.children,
            display: root.display,
            spacing: root.spacing,
            contentInsets: root.contentInsets,
            decoration: root.decoration,
            revision: root.revision
        )
        return RichContentRenderResult(
            snapshot: RichElementSnapshot(root: visibleRoot),
            unhandledNodeTypes: unhandledNodeTypes
        )
    }

    private func build(
        node: RichContentNode,
        context: RichContentRenderContext,
        unhandledNodeTypes: inout Set<RichContentNodeType>
    ) -> RichElement? {
        guard !context.configuration.excludedNodeIDs.contains(node.id) else { return nil }
        if let override = context.resolver?.overrideElement(for: node, context: context) {
            return override
        }
        let providesInlineSequence = node.type == .paragraph || node.type == .heading || node.type == .inline
        let inheritsInlineEdges = node.type == .inline
        let children = node.children.enumerated().compactMap { index, child in
            let childContext = RichContentRenderContext(
                constrainedWidth: context.constrainedWidth,
                configuration: context.configuration,
                resolver: context.resolver,
                needsLeadingInlineSpacing: providesInlineSequence && needsLeadingInlineSpacing(
                    before: index,
                    in: node.children,
                    inherited: inheritsInlineEdges && context.needsLeadingInlineSpacing,
                    excludedNodeIDs: context.configuration.excludedNodeIDs
                ),
                needsTrailingInlineSpacing: providesInlineSequence && needsTrailingInlineSpacing(
                    after: index,
                    in: node.children,
                    inherited: inheritsInlineEdges && context.needsTrailingInlineSpacing,
                    excludedNodeIDs: context.configuration.excludedNodeIDs
                )
            )
            return build(node: child, context: childContext, unhandledNodeTypes: &unhandledNodeTypes)
        }
        guard let builder = registry.builder(for: node.type) else {
            unhandledNodeTypes.insert(node.type)
            return nil
        }
        return builder.build(node: node, children: children, context: context)
    }

    private func needsLeadingInlineSpacing(
        before index: Int,
        in siblings: [RichContentNode],
        inherited: Bool,
        excludedNodeIDs: Set<String>
    ) -> Bool {
        guard index > 0 else { return inherited }
        for sibling in siblings[..<index].reversed() where !excludedNodeIDs.contains(sibling.id) {
            guard let lastCharacter = sibling.plainText.last else { continue }
            return !lastCharacter.isWhitespace
        }
        return inherited
    }

    private func needsTrailingInlineSpacing(
        after index: Int,
        in siblings: [RichContentNode],
        inherited: Bool,
        excludedNodeIDs: Set<String>
    ) -> Bool {
        guard index + 1 < siblings.count else { return inherited }
        for sibling in siblings[(index + 1)...] where !excludedNodeIDs.contains(sibling.id) {
            guard let firstCharacter = sibling.plainText.first else { continue }
            return !firstCharacter.isWhitespace
        }
        return inherited
    }
}
