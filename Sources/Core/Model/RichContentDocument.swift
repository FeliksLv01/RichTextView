import Foundation

/// Rendering content must be an immutable value containing every field affecting output.
public protocol RichContentNodeContent: Sendable, Equatable {}

extension RichContentNodeContent {
    func matches(_ other: any RichContentNodeContent) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

public struct RichEmptyContent: RichContentNodeContent, Equatable {
    public init() {}

}

public struct RichContentNode: Sendable {
    public let id: String
    public let type: RichContentNodeType
    public let content: any RichContentNodeContent
    public let children: [RichContentNode]

    public init(
        id: String,
        type: RichContentNodeType,
        content: any RichContentNodeContent = RichEmptyContent(),
        children: [RichContentNode] = []
    ) {
        precondition(!id.isEmpty, "Rich content node ID must not be empty")
        self.id = id
        self.type = type
        self.content = content
        self.children = children
    }

    public func content<Content: RichContentNodeContent>(as type: Content.Type = Content.self) -> Content? {
        content as? Content
    }

    public func containsNode(ofType nodeType: RichContentNodeType) -> Bool {
        type == nodeType || children.contains { $0.containsNode(ofType: nodeType) }
    }
}

public struct RichContentDocument: Sendable {
    public let root: RichContentNode

    public init(root: RichContentNode) {
        self.root = root
    }

    public init(
        id: String,
        children: [RichContentNode]
    ) {
        root = RichContentNode(
            id: id,
            type: .root,
            children: children
        )
    }

    public var plainText: String {
        root.plainText
    }
}

public extension RichContentNode {
    static func text(
        id: String,
        _ text: String,
        style: RichTextStyle = RichTextStyle()
    ) -> Self {
        Self(
            id: id,
            type: .text,
            content: RichTextContent(text: text, style: style)
        )
    }

    static func paragraph(
        id: String,
        children: [RichContentNode]
    ) -> Self {
        Self(id: id, type: .paragraph, children: children)
    }

    static func paragraph(
        id: String,
        text: String,
        style: RichTextStyle = RichTextStyle()
    ) -> Self {
        paragraph(
            id: id,
            children: [
                .text(id: "\(id).text", text, style: style)
            ]
        )
    }

    var plainText: String {
        if let text = content(as: RichTextContent.self) {
            return text.text
        }
        if let mention = content(as: RichMentionContent.self) {
            return "@\(mention.name)"
        }
        if let emoji = content(as: RichEmojiContent.self) {
            return emoji.name.isEmpty ? emoji.code : emoji.name
        }
        if let image = content(as: RichImageContent.self) {
            return image.title.isEmpty ? "[图片]" : "[\(image.title)]"
        }
        if let math = content(as: RichMathContent.self) {
            return math.isBlock ? "$$\(math.latex)$$" : "\\(\(math.latex)\\)"
        }
        let separator = type == .root ? "\n" : ""
        return children.map(\.plainText).joined(separator: separator)
    }
}
