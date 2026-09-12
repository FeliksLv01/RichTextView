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
        previousDocument: RichContentDocument? = nil
    ) -> RichMarkdownParseResult {
        let markup = Document(parsing: source, options: [.parseBlockDirectives, .parseSymbolLinks])
        return parse(markup, documentID: documentID, previousDocument: previousDocument)
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
        let document = RichContentDocumentReconciler.reconcile(RichContentDocument(root: root), with: previousDocument)
        return RichMarkdownParseResult(
            document: document,
            plainText: document.plainText,
            visibleUnitCount: revealProjector.unitCount(in: document)
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
