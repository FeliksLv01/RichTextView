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
            "Text selection is enabled. Long-press, adjust the handles if needed, then use the anchored Copy menu."
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
            configuration: Self.renderingConfiguration,
            resolver: ExampleContentResolver()
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
                            content: RichImageContent(source: Self.remoteImageURL, title: "Remote GitHub image")
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
                    id: "semantic-colors",
                    type: .paragraph,
                    children: [
                        RichContentNode(
                            id: "foreground-label",
                            type: .text,
                            content: RichTextContent(
                                text: "Custom foreground",
                                style: RichTextStyle(bold: true, foregroundColor: "systemOrange")
                            )
                        ),
                        RichContentNode(id: "color-separator", type: .text, content: RichTextContent(text: " and ")),
                        RichContentNode(
                            id: "background-label",
                            type: .text,
                            content: RichTextContent(
                                text: "semantic background",
                                style: RichTextStyle(backgroundColor: "secondarySystemFill")
                            )
                        )
                    ]
                ),
                RichContentNode(
                    id: "swift-code",
                    type: .codeBlock,
                    content: RichCodeBlockContent(language: "swift"),
                    children: [
                        RichContentNode(
                            id: "swift-code-text",
                            type: .text,
                            content: RichTextContent(text: "let greeting = \"Hello, RichTextView\"\nprint(greeting) // highlighted\nlet renderer = RichContentRenderer().render(document: document, constrainedWidth: 320, configuration: .standard)")
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

    Text before ![Remote GitHub image](https://github.githubassets.com/images/modules/logos_page/GitHub-Logo.png) continues after the network image, demonstrating image and text mixing in Markdown.

    > Block quotes use the same container-node layout as application-built documents.

    1. Ordered list item
    2. A second item with **nested styling**

    - Unordered item
    - Another item with `code`

    ```swift
    let view = RichTextView()
    view.isTextSelectionEnabled = true
    let renderer = RichContentRenderer().render(document: document, constrainedWidth: 320, configuration: .standard)
    ```
    """

    private static let remoteImageURL = "https://github.githubassets.com/images/modules/logos_page/GitHub-Logo.png"

    private static var renderingConfiguration: RichContentRenderingConfiguration {
        let font = UIFont.preferredFont(forTextStyle: .body)
        return RichContentRenderingConfiguration(
            font: font,
            lineHeight: font.lineHeight,
            textColor: .label,
            secondaryTextColor: .secondaryLabel,
            linkColor: .link,
            currentMentionTextColor: .label,
            currentMentionBackgroundColor: .tertiarySystemFill,
            contrastBackgroundColor: .secondarySystemBackground,
            blockQuoteColor: .separator,
            codeBackgroundColor: .tertiarySystemFill,
            codeBlockTextColor: .label,
            codeBlockBackgroundColor: .systemBackground,
            codeBlockInsets: RichContainerInsets(top: 12, left: 16, bottom: 12, right: 16),
            codeBlockCornerRadius: 8,
            highlightTextColor: .label,
            highlightBackgroundColor: UIColor.systemYellow.withAlphaComponent(0.35),
            highlightTokens: ["select", "stable IDs"]
        )
    }
}

private final class ExampleContentResolver: RichContentPresentationResolving {
    private let codeHighlighter = ExampleCodeHighlighter()

    func imagePresentation(
        for node: RichContentNode,
        content: RichImageContent
    ) -> RichInlineImagePresentation? {
        let placeholder = UIImage(systemName: "photo.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        return RichInlineImagePresentation(
            source: RichImageSource(
                identifier: content.source,
                image: placeholder,
                loadsRemotely: content.source.hasPrefix("https://")
            ),
            size: CGSize(width: 64, height: 28),
            copyText: content.title.isEmpty ? "[Image]" : "[\(content.title)]",
            accessibilityLabel: content.title.isEmpty ? "Image" : content.title
        )
    }

    func codeBlockPresentation(
        for node: RichContentNode,
        content: RichCodeBlockContent,
        code: String,
        context: RichContentRenderContext
    ) -> RichCodeBlockPresentation? {
        RichCodeBlockPresentation(
            attributedCode: codeHighlighter.highlight(code: code, language: content.language)
        )
    }
}
