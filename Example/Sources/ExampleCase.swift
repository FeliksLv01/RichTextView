import RichTextView
import RichTextViewMarkdown
import UIKit

enum ExampleCase: String, CaseIterable {
    case string
    case attributedImageMix
    case nodeTree
    case table
    case markdownSelection
    case math
    case markdownStreaming

    var title: String {
        switch self {
        case .math: "LaTeX formulas"
        case .string: "String and actions"
        case .attributedImageMix: "Attributed image and text"
        case .nodeTree: "Complex unified node tree"
        case .table: "Scrollable rich table"
        case .markdownSelection: "Markdown with selection"
        case .markdownStreaming: "Streaming Markdown typewriter"
        }
    }

    var summary: String {
        switch self {
        case .math: "Inline math, fractions, cases, matrices, and boxed answers"
        case .string: "Multiline text, truncation, and tappable ranges"
        case .attributedImageMix: "Styled runs and inline images in NSAttributedString"
        case .nodeTree: "Heading, mention, link, image, quote, list, and emoji"
        case .table: "Rich cells, column alignment, selection, and horizontal scrolling"
        case .markdownSelection: "Rich Markdown normalized into selectable nodes"
        case .markdownStreaming: "Partial Markdown, stable elements, and progressive formulas"
        }
    }

    var note: String {
        switch self {
        case .math:
            "Native formula drawing with selection and copy. Tap Replay to watch partially received formulas grow."
        case .string:
            "A lightweight entry point that still uses the same layout and drawing engine."
        case .attributedImageMix:
            "Inline images participate in line breaking, baseline alignment, selection, and copy semantics."
        case .nodeTree:
            "Application data is represented by stable node IDs and rendered without going through Markdown."
        case .table:
            "The table is a built-in rich-text node. Swipe horizontally to inspect every column; selecting it copies tab-separated rows."
        case .markdownSelection:
            "Text selection is enabled. Long-press, adjust the handles if needed, then use the anchored Copy menu."
        case .markdownStreaming:
            "One character arrives every 20 ms. Unchanged elements are reused; incomplete formulas use a temporary preview."
        }
    }

    var supportsSelection: Bool {
        self != .string
    }

    @MainActor
    func apply(
        to richTextView: RichTextView,
        constrainedWidth: CGFloat,
        resolver: any RichContentPresentationResolving
    ) {
        switch self {
        case .math:
            let parsed = RichMarkdownParser(imageSize: CGSize(width: 24, height: 24)).parse(Self.mathMarkdown, documentID: "math-example")
            apply(document: parsed.document, to: richTextView, constrainedWidth: constrainedWidth, resolver: resolver)
        case .string:
            applyString(to: richTextView)
        case .attributedImageMix:
            applyAttributedImageMix(to: richTextView)
        case .nodeTree:
            apply(
                document: Self.nodeTreeDocument,
                to: richTextView,
                constrainedWidth: constrainedWidth,
                resolver: resolver
            )
        case .table:
            let parsed = RichMarkdownParser(imageSize: CGSize(width: 24, height: 24)).parse(
                Self.tableMarkdown,
                documentID: "table-example"
            )
            apply(
                document: parsed.document,
                to: richTextView,
                constrainedWidth: constrainedWidth,
                resolver: resolver
            )
        case .markdownSelection:
            let parsed = RichMarkdownParser(imageSize: CGSize(width: 64, height: 28)).parse(
                Self.markdown,
                documentID: "markdown-example"
            )
            apply(
                document: parsed.document,
                to: richTextView,
                constrainedWidth: constrainedWidth,
                resolver: resolver
            )
        case .markdownStreaming:
            richTextView.setContent(
                RichContentDocument(id: "streaming-example", children: []),
                configuration: Self.renderingConfiguration,
                resolver: resolver
            )
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
    func apply(
        document: RichContentDocument,
        to richTextView: RichTextView,
        constrainedWidth: CGFloat,
        resolver: any RichContentPresentationResolving
    ) {
        richTextView.setContent(
            document,
            configuration: Self.renderingConfiguration,
            resolver: resolver
        )
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

    static let mathMarkdown = #"""
    ## Inline math
    Energy \(E = mc^2\) and the identity \(e^{i\pi}+1=0\) share the text baseline.

    ## Fractions & roots
    $$
    x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
    $$

    ## Piecewise functions
    $$
    f(n) = \begin{cases} 0, & \text{odd} \\ n, & \text{even} \end{cases}
    $$

    ## Matrices
    $$
    A = \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}
    $$

    ## Boxed answers
    $$
    \boxed{\text{答案：} \sum_{k=1}^{n} k = \frac{n(n+1)}{2}}
    $$
    """#

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
                            content: RichImageContent(
                                source: Self.remoteImageURL,
                                title: "Remote GitHub image",
                                size: CGSize(width: 64, height: 28)
                            )
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

    | Component | Responsibility | Streaming behavior |
    | :-- | :-- | --: |
    | Node tree | Stable semantic content | Reconciled by node ID |
    | Table | Nested rich cell content | Rows update without replacing the outer attachment |
    | Code block | Tree-sitter highlighting | Incremental syntax tree reuse |

    ```swift
    let view = RichTextView()
    view.isTextSelectionEnabled = true
    let renderer = RichContentRenderer().render(document: document, constrainedWidth: 320, configuration: .standard)
    ```
    """

    private static let tableMarkdown = """
    # Rich table

    Table cells use the same rendering pipeline as the surrounding document.

    | Component | Rendering | Streaming behavior | Status |
    | :-- | :-- | :-- | --: |
    | **Node tree** | Stable semantic content with `inline code` | Reconciles by node ID | Ready |
    | [Links](https://github.com/FeliksLv01/RichTextView) | Remain tappable inside rich cells | Reuses unchanged cell layouts | Ready |
    | Long content | Columns grow up to the configured maximum width and rows expand vertically when content wraps | The outer attachment keeps its identity while rows change | 100% |
    | Selection | The table is one selectable attachment | Copy produces tab-separated rows | Enabled |

    Swipe the table horizontally to reveal the Status column.
    """

    private static let remoteImageURL = "https://github.githubassets.com/images/modules/logos_page/GitHub-Logo.png"

    static var renderingConfiguration: RichContentRenderingConfiguration {
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

final class ExampleContentResolver: RichContentPresentationResolving {
    let inputs = false
    func imageSource(
        for node: RichContentNode,
        content: RichImageContent
    ) -> RichImageSource? {
        let placeholder = UIImage(systemName: "photo.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        return RichImageSource(
            identifier: content.source,
            image: placeholder,
            loadsRemotely: content.source.hasPrefix("https://")
        )
    }

}
