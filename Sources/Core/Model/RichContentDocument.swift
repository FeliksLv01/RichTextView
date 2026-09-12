import Foundation

public struct RichContentRevision: Hashable, Sendable {
    public let layout: Int
    public let display: Int

    public init(layout: Int = 0, display: Int = 0) {
        self.layout = layout
        self.display = display
    }

    public static let initial = RichContentRevision()
}

public protocol RichContentNodeContent: Sendable {}

public protocol RichContentNodeContentSignatureProviding {
    var richContentLayoutSignature: String { get }
    var richContentDisplaySignature: String { get }
}

public extension RichContentNodeContentSignatureProviding {
    var richContentDisplaySignature: String { richContentLayoutSignature }
}

public struct RichEmptyContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public init() {}

    public var richContentLayoutSignature: String { "empty" }
}

public struct RichContentNode: Sendable {
    public let id: String
    public let type: RichContentNodeType
    public let content: any RichContentNodeContent
    public let children: [RichContentNode]
    public let revision: RichContentRevision

    public init(
        id: String,
        type: RichContentNodeType,
        content: any RichContentNodeContent = RichEmptyContent(),
        children: [RichContentNode] = [],
        revision: RichContentRevision = .initial
    ) {
        precondition(!id.isEmpty, "Rich content node ID must not be empty")
        self.id = id
        self.type = type
        self.content = content
        self.children = children
        self.revision = revision
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

    public var plainText: String {
        root.plainText
    }
}

public extension RichContentNode {
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
        let separator = type == .root ? "\n" : ""
        return children.map(\.plainText).joined(separator: separator)
    }
}
