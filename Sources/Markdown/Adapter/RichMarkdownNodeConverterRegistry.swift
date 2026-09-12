import Markdown
#if SWIFT_PACKAGE
import RichTextView
#endif

public struct RichMarkdownNodeConverterRegistry {
    private let convertersByType: [ObjectIdentifier: any RichMarkdownNodeConverting]

    public init(converters: [any RichMarkdownNodeConverting]) {
        var values: [ObjectIdentifier: any RichMarkdownNodeConverting] = [:]
        for converter in converters {
            let key = ObjectIdentifier(converter.markupType)
            precondition(values[key] == nil, "Duplicate Markdown converter: \(converter.markupType)")
            values[key] = converter
        }
        convertersByType = values
    }

    public func converter(for markup: any Markup) -> (any RichMarkdownNodeConverting)? {
        convertersByType[ObjectIdentifier(type(of: markup))]
    }

    public func registering(_ converter: any RichMarkdownNodeConverting) -> Self {
        let key = ObjectIdentifier(converter.markupType)
        precondition(convertersByType[key] == nil, "Duplicate Markdown converter: \(converter.markupType)")
        return Self(converters: Array(convertersByType.values) + [converter])
    }

    public func replacing(_ converter: any RichMarkdownNodeConverting) -> Self {
        let key = ObjectIdentifier(converter.markupType)
        precondition(convertersByType[key] != nil, "No Markdown converter to replace: \(converter.markupType)")
        var values = convertersByType
        values[key] = converter
        return Self(converters: Array(values.values))
    }
}

public extension RichMarkdownNodeConverterRegistry {
    static func standard(
        htmlResolver: (any RichMarkdownHTMLResolving)? = nil
    ) -> RichMarkdownNodeConverterRegistry {
        RichMarkdownNodeConverterRegistry(converters: [
            RichMarkdownDocumentConverter(),
            RichMarkdownParagraphConverter(),
            RichMarkdownHeadingConverter(),
            RichMarkdownTextConverter(),
            RichMarkdownStrongConverter(),
            RichMarkdownEmphasisConverter(),
            RichMarkdownStrikethroughConverter(),
            RichMarkdownInlineCodeConverter(),
            RichMarkdownSoftBreakConverter(),
            RichMarkdownLineBreakConverter(),
            RichMarkdownLinkConverter(),
            RichMarkdownImageConverter(),
            RichMarkdownOrderedListConverter(),
            RichMarkdownUnorderedListConverter(),
            RichMarkdownListItemConverter(),
            RichMarkdownBlockQuoteConverter(),
            RichMarkdownCodeBlockConverter(),
            RichMarkdownThematicBreakConverter(),
            RichMarkdownTableConverter(),
            RichMarkdownTableHeadConverter(),
            RichMarkdownTableBodyConverter(),
            RichMarkdownTableRowConverter(),
            RichMarkdownTableCellConverter(),
            RichMarkdownInlineHTMLConverter(resolver: htmlResolver),
            RichMarkdownHTMLBlockConverter(resolver: htmlResolver)
        ])
    }
}
