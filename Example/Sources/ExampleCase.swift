import RichTextView
import RichTextViewMarkdown
import UIKit

enum ExampleCase: CaseIterable {
    case string
    case attributedImageMix
    case nodeTree
    case markdownSelection

    var title: String {
        switch self {
        case .string: "String and actions"
        case .attributedImageMix: "Attributed image and text"
        case .nodeTree: "Complex unified node tree"
        case .markdownSelection: "Markdown with selection"
        }
    }

    var summary: String {
        switch self {
        case .string: "Multiline text, truncation, and tappable ranges"
        case .attributedImageMix: "Styled runs and inline images in NSAttributedString"
        case .nodeTree: "Heading, mention, link, image, quote, list, and emoji"
        case .markdownSelection: "Rich Markdown normalized into selectable nodes"
        }
    }

    var note: String {
        switch self {
        case .string:
            "A lightweight entry point that still uses the same layout and drawing engine."
        case .attributedImageMix:
            "Inline images participate in line breaking, baseline alignment, selection, and copy semantics."
        case .nodeTree:
            "Application data is represented by stable node IDs and rendered without going through Markdown."
        case .markdownSelection:
            "Text selection is enabled. Long-press the rendered content to select text and use the copy menu."
        }
    }

    var supportsSelection: Bool {
        self == .attributedImageMix || self == .nodeTree || self == .markdownSelection
    }

    @MainActor
    func apply(to richTextView: RichTextView, constrainedWidth: CGFloat) {
        switch self {
        case .string:
            applyString(to: richTextView)
        case .attributedImageMix:
            applyAttributedImageMix(to: richTextView)
        case .nodeTree:
            apply(document: Self.nodeTreeDocument, to: richTextView, constrainedWidth: constrainedWidth)
        case .markdownSelection:
            let parsed = RichMarkdownParser().parse(Self.markdown, documentID: "markdown-example")
            apply(document: parsed.document, to: richTextView, constrainedWidth: constrainedWidth)
        }
    }

    @MainActor
    private func applyString(to richTextView: RichTextView) {
        let text = "RichTextView renders multiline String values directly. Tap this documentation range to exercise action hit-testing."
        richTextView.text = text
        if let range = text.range(of: "documentation range") {
            richTextView.setTextAction("example:documentation", range: NSRange(range, in: text))
        }
    }

    @MainActor
    private func applyAttributedImageMix(to richTextView: RichTextView) {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let content = NSMutableAttributedString(
            string: "Text before the image  ",
            attributes: [.font: font, .foregroundColor: UIColor.label]
        )
        content.append(Self.inlineImage(
            id: "attributed-photo",
            systemName: "photo.fill",
            color: .systemBlue,
            font: font,
            label: "Photo"
        ).attributedString)
        content.append(NSAttributedString(
            string: "  continues on the same line. A second icon ",
            attributes: [.font: font, .foregroundColor: UIColor.secondaryLabel]
        ))
        content.append(Self.inlineImage(
            id: "attributed-star",
            systemName: "star.fill",
            color: .systemOrange,
            font: font,
            label: "Favorite"
        ).attributedString)
        content.append(NSAttributedString(
            string: " also participates in wrapping and selection.",
            attributes: [.font: font, .foregroundColor: UIColor.label]
        ))
        richTextView.attributedText = content
    }

    @MainActor
    private func apply(
        document: RichContentDocument,
        to richTextView: RichTextView,
        constrainedWidth: CGFloat
    ) {
        let result = RichContentRenderer().render(
            document: document,
            constrainedWidth: constrainedWidth,
            configuration: .standard,
            resolver: ExampleImageResolver()
        )
        richTextView.apply(result.snapshot)
    }

    @MainActor
    private static func inlineImage(
        id: String,
        systemName: String,
        color: UIColor,
        font: UIFont,
        label: String
    ) -> RichAttributedInlineImage {
        RichAttributedInlineImage(
            id: id,
            source: RichImageSource(
                identifier: systemName,
                image: UIImage(systemName: systemName)?.withTintColor(color, renderingMode: .alwaysOriginal)
            ),
            size: CGSize(width: 24, height: 22),
            font: font,
            copyText: "[\(label)]",
            accessibilityLabel: label
        )
    }

    private static let nodeTreeDocument = RichContentDocument(
        root: RichContentNode(
            id: "article",
            type: .root,
            children: [
                RichContentNode(
                    id: "heading",
                    type: .heading,
                    content: RichHeadingContent(level: 2),
                    children: [
                        RichContentNode(
                            id: "heading-text",
                            type: .text,
                            content: RichTextContent(
                                text: "A document assembled from typed nodes",
                                style: RichTextStyle(bold: true, fontScale: 1.35)
                            )
                        )
                    ]
                ),
                RichContentNode(
                    id: "mixed-paragraph",
                    type: .paragraph,
                    children: [
                        RichContentNode(id: "intro", type: .text, content: RichTextContent(text: "Hello ")),
                        RichContentNode(
                            id: "mention",
                            type: .mention,
                            content: RichMentionContent(id: "reader", name: "reader", mentionType: "user")
                        ),
                        RichContentNode(id: "link-prefix", type: .text, content: RichTextContent(text: ", open ")),
                        RichContentNode(
                            id: "link",
                            type: .link,
                            content: RichLinkContent(href: "https://github.com", title: "GitHub", icon: ""),
                            children: [
                                RichContentNode(id: "link-text", type: .text, content: RichTextContent(text: "GitHub"))
                            ]
                        ),
                        RichContentNode(id: "image-prefix", type: .text, content: RichTextContent(text: ", then inspect ")),
                        RichContentNode(
                            id: "inline-image",
                            type: .image,
                            content: RichImageContent(source: "example://photo", title: "Photo")
                        ),
                        RichContentNode(id: "emoji-prefix", type: .text, content: RichTextContent(text: " and reusable nodes ")),
                        RichContentNode(id: "emoji", type: .emoji, content: RichEmojiContent(code: ":sparkles:", name: "✨"))
                    ]
                ),
                RichContentNode(
                    id: "quote",
                    type: .blockQuote,
                    children: [
                        RichContentNode(
                            id: "quote-text",
                            type: .text,
                            content: RichTextContent(
                                text: "The renderer consumes one stable tree regardless of the source format.",
                                style: RichTextStyle(italic: true)
                            )
                        )
                    ]
                ),
                RichContentNode(
                    id: "list-one",
                    type: .numberedList,
                    content: RichListContent(level: 1, index: 1),
                    children: [
                        RichContentNode(id: "list-one-text", type: .text, content: RichTextContent(text: "Reconcile stable IDs"))
                    ]
                ),
                RichContentNode(
                    id: "list-two",
                    type: .numberedList,
                    content: RichListContent(level: 1, index: 2),
                    children: [
                        RichContentNode(id: "list-two-text", type: .text, content: RichTextContent(text: "Reuse layout and render objects"))
                    ]
                )
            ]
        )
    )

    private static let markdown = """
    # Markdown document

    Long-press anywhere in this document to select and copy text. The parser supports **bold**, *italic*, `inline code`, [links](https://github.com), and ~~double-tilde strikethrough~~.

    Text before ![Photo](example://photo) continues after the inline image, demonstrating image and text mixing in Markdown.

    > Block quotes use the same container-node layout as application-built documents.

    1. Ordered list item
    2. A second item with **nested styling**

    - Unordered item
    - Another item with `code`

    ```swift
    let view = RichTextView()
    view.isTextSelectionEnabled = true
    ```
    """
}

private final class ExampleImageResolver: RichContentPresentationResolving {
    func imagePresentation(
        for node: RichContentNode,
        content: RichImageContent
    ) -> RichInlineImagePresentation? {
        let image = UIImage(systemName: "photo.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        return RichInlineImagePresentation(
            source: RichImageSource(identifier: content.source, image: image),
            size: CGSize(width: 26, height: 22),
            copyText: content.title.isEmpty ? "[Image]" : "[\(content.title)]",
            accessibilityLabel: content.title.isEmpty ? "Image" : content.title
        )
    }
}
