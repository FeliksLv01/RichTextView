import Markdown
#if SWIFT_PACKAGE
import RichTextView
#endif

public enum RichMarkdownListKind: Sendable {
    case none
    case ordered(start: Int)
    case unordered
}

public struct RichMarkdownConversionContext: Sendable {
    public let documentID: String
    public let path: [Int]
    public let textStyle: RichTextStyle
    public let listKind: RichMarkdownListKind
    public let listLevel: Int
    public let tableColumnAlignments: [RichTableCellAlignment]

    public init(
        documentID: String,
        path: [Int] = [],
        textStyle: RichTextStyle = RichTextStyle(),
        listKind: RichMarkdownListKind = .none,
        listLevel: Int = 0,
        tableColumnAlignments: [RichTableCellAlignment] = []
    ) {
        self.documentID = documentID
        self.path = path
        self.textStyle = textStyle
        self.listKind = listKind
        self.listLevel = listLevel
        self.tableColumnAlignments = tableColumnAlignments
    }

    public var nodeID: String {
        path.isEmpty ? documentID : "\(documentID)/\(path.map(String.init).joined(separator: "/"))"
    }

    public func appendingPath(_ index: Int) -> Self {
        Self(
            documentID: documentID,
            path: path + [index],
            textStyle: textStyle,
            listKind: listKind,
            listLevel: listLevel,
            tableColumnAlignments: tableColumnAlignments
        )
    }

    public func replacing(
        textStyle: RichTextStyle? = nil,
        listKind: RichMarkdownListKind? = nil,
        listLevel: Int? = nil,
        tableColumnAlignments: [RichTableCellAlignment]? = nil
    ) -> Self {
        Self(
            documentID: documentID,
            path: path,
            textStyle: textStyle ?? self.textStyle,
            listKind: listKind ?? self.listKind,
            listLevel: listLevel ?? self.listLevel,
            tableColumnAlignments: tableColumnAlignments ?? self.tableColumnAlignments
        )
    }
}

public protocol RichMarkdownNodeConverting {
    var markupType: Any.Type { get }

    func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext

    func convert(
        _ markup: any Markup,
        children: [RichContentNode],
        context: RichMarkdownConversionContext
    ) -> [RichContentNode]
}

public extension RichMarkdownNodeConverting {
    func contextForChildren(
        of markup: any Markup,
        context: RichMarkdownConversionContext
    ) -> RichMarkdownConversionContext {
        context
    }
}

public protocol RichMarkdownHTMLResolving: Sendable {
    func resolve(
        literal: String,
        isBlock: Bool,
        context: RichMarkdownConversionContext
    ) -> [RichContentNode]?
}
