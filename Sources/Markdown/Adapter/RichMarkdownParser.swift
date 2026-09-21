import CoreGraphics
import Markdown
#if SWIFT_PACKAGE
import RichTextView
#endif

public struct RichMarkdownParseResult: Sendable {
    public let document: RichContentDocument
    public let plainText: String
    public let visibleUnitCount: Int

    public init(document: RichContentDocument, plainText: String, visibleUnitCount: Int) {
        self.document = document
        self.plainText = plainText
        self.visibleUnitCount = visibleUnitCount
    }
}

public struct RichMarkdownParser {
    private let registry: RichMarkdownNodeConverterRegistry
    private let revealProjector = RichContentDocumentRevealProjector()

    public init(imageSize: CGSize) {
        registry = .standard(imageSize: imageSize)
    }

    public init(registry: RichMarkdownNodeConverterRegistry) {
        self.registry = registry
    }

    public func parse(
        _ source: String,
        documentID: String,
        previousDocument: RichContentDocument? = nil,
        streaming: Bool = false
    ) -> RichMarkdownParseResult {
        let markup = Document(parsing: Self.preprocessMath(source), options: [.parseBlockDirectives, .parseSymbolLinks])
        let result = parse(markup, documentID: documentID, previousDocument: previousDocument)
        guard streaming, Self.endsInsideFencedCode(source) else { return result }
        let (root, marked) = markingLastCodeBlockStreaming(in: result.document.root)
        guard marked else { return result }
        let document = RichContentDocument(root: root)
        return RichMarkdownParseResult(
            document: document,
            plainText: document.plainText,
            visibleUnitCount: revealProjector.unitCount(in: document)
        )
    }

    public func parse(
        _ markup: Document,
        documentID: String,
        previousDocument: RichContentDocument? = nil
    ) -> RichMarkdownParseResult {
        let context = RichMarkdownConversionContext(documentID: documentID)
        let nodes = convert(markup, context: context)
        let root = nodes.first(where: { $0.type == .root })
            ?? RichContentNode(id: documentID, type: .root, children: nodes)
        let document = RichContentDocument(root: root)
        return RichMarkdownParseResult(
            document: document,
            plainText: document.plainText,
            visibleUnitCount: revealProjector.unitCount(in: document)
        )
    }

    private static func preprocessMath(_ source: String) -> String {
        source
            .replacingOccurrences(
                of: #"(?ms)^[\t ]*\$\$(?:\r?\n)?(.+?)(?:\r?\n)?[\t ]*\$\$[\t ]*$"#,
                with: "```blockmath\n$1\n```",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?ms)^[\t ]*\\\[(?:\r?\n)?(.+?)(?:\r?\n)?[\t ]*\\\][\t ]*$"#,
                with: "```blockmath\n$1\n```",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\\\((.+?)\\\)"#,
                with: "`richmath:$1`",
                options: .regularExpression
            )
    }

    private static func endsInsideFencedCode(_ source: String) -> Bool {
        var fence: (marker: Character, length: Int)?
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            guard let marker = trimmed.first, marker == "`" || marker == "~" else { continue }
            let length = trimmed.prefix(while: { $0 == marker }).count
            guard length >= 3 else { continue }
            if let current = fence {
                if marker == current.marker, length >= current.length { fence = nil }
            } else {
                fence = (marker, length)
            }
        }
        return fence != nil
    }

    private func markingLastCodeBlockStreaming(in node: RichContentNode) -> (RichContentNode, Bool) {
        var children = node.children
        for index in children.indices.reversed() {
            let (child, marked) = markingLastCodeBlockStreaming(in: children[index])
            guard marked else { continue }
            children[index] = child
            return (RichContentNode(id: node.id, type: node.type, content: node.content, children: children), true)
        }
        guard node.type == .codeBlock else { return (node, false) }
        let content = node.content(as: RichCodeBlockContent.self) ?? RichCodeBlockContent()
        return (
            RichContentNode(
                id: node.id,
                type: node.type,
                content: RichCodeBlockContent(language: content.language, isStreaming: true),
                children: children
            ),
            true
        )
    }

    private func convert(
        _ markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> [RichContentNode] {
        guard let converter = registry.converter(for: markup) else {
            return markup.children.enumerated().flatMap { index, child in
                convert(child, context: context.appendingPath(index))
            }
        }
        let childContext = converter.contextForChildren(of: markup, context: context)
        let children = markup.children.enumerated().flatMap { index, child in
            convert(child, context: childContext.appendingPath(index))
        }
        return converter.convert(markup, children: children, context: context)
    }

}
