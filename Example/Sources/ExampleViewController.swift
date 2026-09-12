import RichTextView
import RichTextViewMarkdown
import UIKit

final class ExampleViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let nodeTreeTitleLabel = UILabel()
    private let nodeTreeView = RichTextView()
    private let markdownTitleLabel = UILabel()
    private let markdownView = RichTextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "RichTextView"
        view.backgroundColor = .systemBackground
        configureViews()
        renderNodeTree()
        renderMarkdown()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds

        let horizontalInset: CGFloat = 20
        let contentWidth = max(0, scrollView.bounds.width - horizontalInset * 2)
        var currentY: CGFloat = 24

        currentY = layout(title: nodeTreeTitleLabel, richTextView: nodeTreeView, y: currentY, width: contentWidth)
        currentY += 28
        currentY = layout(title: markdownTitleLabel, richTextView: markdownView, y: currentY, width: contentWidth)

        contentView.frame = CGRect(
            x: horizontalInset,
            y: 0,
            width: contentWidth,
            height: currentY + 32
        )
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: contentView.frame.height)
    }

    private func configureViews() {
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        configureTitleLabel(nodeTreeTitleLabel, text: "Unified node tree")
        configureTitleLabel(markdownTitleLabel, text: "Markdown adapter")
        configureRichTextView(nodeTreeView)
        configureRichTextView(markdownView)

        [nodeTreeTitleLabel, nodeTreeView, markdownTitleLabel, markdownView].forEach(contentView.addSubview)
    }

    private func configureTitleLabel(_ label: UILabel, text: String) {
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.text = text
    }

    private func configureRichTextView(_ richTextView: RichTextView) {
        richTextView.backgroundColor = .secondarySystemBackground
        richTextView.layer.cornerRadius = 12
        richTextView.isTextSelectionEnabled = true
    }

    private func renderNodeTree() {
        let document = RichContentDocument(
            root: RichContentNode(
                id: "node-example",
                type: .root,
                children: [
                    RichContentNode(
                        id: "node-heading",
                        type: .heading,
                        content: RichHeadingContent(level: 2),
                        children: [
                            RichContentNode(
                                id: "node-heading-text",
                                type: .text,
                                content: RichTextContent(
                                    text: "One renderer, one node tree",
                                    style: RichTextStyle(bold: true, fontScale: 1.25)
                                )
                            )
                        ]
                    ),
                    RichContentNode(
                        id: "node-paragraph",
                        type: .paragraph,
                        children: [
                            RichContentNode(
                                id: "node-paragraph-text",
                                type: .text,
                                content: RichTextContent(
                                    text: "Application models and document formats share the same rendering pipeline."
                                )
                            )
                        ]
                    )
                ]
            )
        )
        apply(document, to: nodeTreeView)
    }

    private func renderMarkdown() {
        let markdown = """
        ## Markdown is an adapter

        It produces the **same node tree**, including lists, links, and ~~strikethrough~~.

        - CoreText layout
        - Selection and interaction
        - Custom attachments
        """
        let result = RichMarkdownParser().parse(markdown, documentID: "markdown-example")
        apply(result.document, to: markdownView)
    }

    private func apply(_ document: RichContentDocument, to richTextView: RichTextView) {
        let result = RichContentRenderer().render(
            document: document,
            constrainedWidth: max(0, view.bounds.width - 40),
            configuration: .standard
        )
        richTextView.apply(result.snapshot)
    }

    private func layout(title: UILabel, richTextView: RichTextView, y: CGFloat, width: CGFloat) -> CGFloat {
        let titleHeight = title.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        title.frame = CGRect(x: 0, y: y, width: width, height: titleHeight)

        let richTextY = title.frame.maxY + 12
        let contentWidth = max(0, width - 32)
        let contentSize = richTextView.sizeThatFits(
            CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
        richTextView.frame = CGRect(
            x: 0,
            y: richTextY,
            width: width,
            height: contentSize.height + 32
        )
        return richTextView.frame.maxY
    }
}
