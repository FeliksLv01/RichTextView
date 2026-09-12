import Foundation

public struct RichContentElementBuilderRegistry {
    private let buildersByType: [RichContentNodeType: any RichContentElementBuilding]

    public init(builders: [any RichContentElementBuilding]) {
        var result: [RichContentNodeType: any RichContentElementBuilding] = [:]
        for builder in builders {
            precondition(result[builder.nodeType] == nil, "Duplicate rich element builder: \(builder.nodeType.rawValue)")
            result[builder.nodeType] = builder
        }
        buildersByType = result
    }

    public func builder(for nodeType: RichContentNodeType) -> (any RichContentElementBuilding)? {
        buildersByType[nodeType]
    }

    public func registering(_ builder: any RichContentElementBuilding) -> Self {
        precondition(buildersByType[builder.nodeType] == nil, "Duplicate rich element builder: \(builder.nodeType.rawValue)")
        return Self(builders: Array(buildersByType.values) + [builder])
    }

    public func replacing(_ builder: any RichContentElementBuilding) -> Self {
        var builders = buildersByType
        precondition(builders.updateValue(builder, forKey: builder.nodeType) != nil, "No rich element builder to replace: \(builder.nodeType.rawValue)")
        return Self(builders: Array(builders.values))
    }
}

public extension RichContentElementBuilderRegistry {
    static var standard: RichContentElementBuilderRegistry {
        RichContentElementBuilderRegistry(builders: [
            RichRootElementBuilder(), RichParagraphElementBuilder(), RichInlineElementBuilder(),
            RichHeadingElementBuilder(),
            RichCodeBlockElementBuilder(),
            RichDividerElementBuilder(),
            RichColumnsElementBuilder(), RichColumnElementBuilder(), RichReferenceElementBuilder(),
            RichNumberedListElementBuilder(), RichBulletedListElementBuilder(), RichBlockQuoteElementBuilder(),
            RichTextElementBuilder(), RichMentionElementBuilder(), RichEmojiElementBuilder(),
            RichImageElementBuilder(), RichLinkElementBuilder(), RichCommandElementBuilder()
        ])
    }
}
