
import UIKit

public struct RichContentRenderResult: Sendable {
    public let snapshot: RichElementSnapshot
    public let unhandledNodeTypes: Set<RichContentNodeType>

    public init(snapshot: RichElementSnapshot, unhandledNodeTypes: Set<RichContentNodeType>) {
        self.snapshot = snapshot
        self.unhandledNodeTypes = unhandledNodeTypes
    }
}

public final class RichContentRenderer {
    private let registry: RichContentElementBuilderRegistry

    private struct Entry {
        let type: RichContentNodeType
        let content: any RichContentNodeContent
        let builderKey: AnyHashable
        let children: [RichElement]
        let leading: Bool
        let trailing: Bool
        let element: RichElement
    }
    private let lock = NSRecursiveLock()
    private var entries: [String: Entry] = [:]
    private var previousConfiguration: RichContentRenderingConfiguration?
    private var previousTraits: UITraitCollection?
    private var previousStreaming = false
    private var previousWidth: CGFloat?
    private var previousResolverKey: AnyHashable?
    private var previousResolverType: ObjectIdentifier?
    private var visited: Set<String> = []

    public init(registry: RichContentElementBuilderRegistry? = nil) {
        self.registry = registry ?? .standard
    }

    public func render(
        document: RichContentDocument,
        constrainedWidth: CGFloat,
        configuration: RichContentRenderingConfiguration,
        resolver: (any RichContentPresentationResolving)? = nil,
        streaming: Bool = false
    ) -> RichContentRenderResult {
        lock.lock()
        defer { lock.unlock() }
        let resolverKey = resolver.map { AnyHashable($0.inputs) }
        let resolverType = resolver.map { ObjectIdentifier(type(of: $0)) }
        let reusable = (resolver == nil || resolverKey != nil) && configuration.textForegroundColorResolver == nil
            && configuration.leadingElements.isEmpty
        if !reusable || previousStreaming != streaming || previousResolverKey != resolverKey || previousResolverType != resolverType || previousWidth != constrainedWidth || previousTraits != UITraitCollection.current
            || previousConfiguration?.matchesForReuse(configuration) != true {
            entries.removeAll()
        }
        previousStreaming = streaming
        previousResolverKey = resolverKey
        previousResolverType = resolverType
        previousWidth = constrainedWidth
        previousTraits = UITraitCollection.current
        previousConfiguration = configuration
        visited.removeAll(keepingCapacity: true)
        defer {
            entries = reusable ? entries.filter { visited.contains($0.key) } : [:]
        }
        var unhandledNodeTypes: Set<RichContentNodeType> = []
        let context = RichContentRenderContext(
            constrainedWidth: constrainedWidth,
            configuration: configuration,
            resolver: resolver,
            streaming: streaming
        )
        let root = build(node: document.root, context: context, unhandledNodeTypes: &unhandledNodeTypes)
            as? RichContainerElement ?? RichContainerElement(id: document.root.id, children: [])
        let visibleRoot = RichContainerElement(
            id: root.id,
            children: configuration.leadingElements + root.children,
            display: root.display,
            spacing: root.spacing,
            contentInsets: root.contentInsets,
            decoration: root.decoration
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
        let providesInlineSequence = node.type == .paragraph || node.type == .heading || node.type == .inline
        let inheritsInlineEdges = node.type == .inline
        let children = node.children.enumerated().compactMap { index, child in
            let childContext = RichContentRenderContext(
                constrainedWidth: context.constrainedWidth,
                configuration: context.configuration,
                resolver: context.resolver,
                streaming: context.streaming,
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
            if let override = context.resolver?.overrideElement(for: node, context: context) { return override }
            unhandledNodeTypes.insert(node.type)
            return nil
        }
        let builderKey = AnyHashable(builder.inputs)
        // Code highlighting reads a globally replaceable plugin, outside these inputs.
        let cacheable = children.count == node.children.count && node.type != .codeBlock && context.configuration.textForegroundColorResolver == nil
            && context.configuration.leadingElements.isEmpty
        visited.insert(node.id)
        if cacheable, let entry = entries[node.id], entry.type == node.type,
           entry.builderKey == builderKey,
           entry.content.matches(node.content),
           entry.leading == context.needsLeadingInlineSpacing,
           entry.trailing == context.needsTrailingInlineSpacing,
           entry.children.count == children.count,
           zip(entry.children, children).allSatisfy({ $0 === $1 }) {
            return entry.element
        }
        let element = context.resolver?.overrideElement(for: node, context: context)
            ?? builder.build(node: node, children: children, context: context)
        if cacheable, let element {
            entries[node.id] = Entry(type: node.type, content: node.content, builderKey: builderKey, children: children,
                leading: context.needsLeadingInlineSpacing, trailing: context.needsTrailingInlineSpacing, element: element)
        } else {
            entries.removeValue(forKey: node.id)
        }
        return element
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
