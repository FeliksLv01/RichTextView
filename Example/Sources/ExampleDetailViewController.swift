import RichTextView
import SafariServices
import UIKit

final class ExampleDetailViewController: UIViewController, UIScrollViewDelegate {
    private let example: ExampleCase
    private let scrollView = UIScrollView()
    private let noteLabel = UILabel()
    private let imageLoader = ExampleRemoteImageLoader()
    private let selectionMenuPresenter = ExampleSelectionMenuPresenter()
    private let contentResolver = ExampleContentResolver()
    private lazy var richTextView = RichTextView(imageLoader: imageLoader)
    private lazy var markdownTypewriter = ExampleMarkdownTypewriter(source: example == .math ? ExampleCase.mathMarkdown : nil) { [weak self] update in
        self?.applyTypewriterUpdate(update)
    }
    private let streamingRenderer = RichContentRenderer()
    private let streamingLayoutEngine = RichTextLayoutEngine()
    private var renderedWidth: CGFloat = 0
    private var followsStreamingContent = true
    private var needsStreamingScrollToBottom = false
    private var streamingDocument: RichContentDocument?

    init(example: ExampleCase) {
        self.example = example
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = example.title
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemBackground
        configureViews()
        if example == .markdownStreaming || example == .math {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Replay",
                style: .plain,
                target: self,
                action: #selector(restartTypewriter)
            )
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if example == .markdownStreaming || (example == .math && ProcessInfo.processInfo.arguments.contains("--replay")) {
            markdownTypewriter.start()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        markdownTypewriter.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds

        let horizontalInset: CGFloat = 20
        let contentWidth = max(0, scrollView.bounds.width - horizontalInset * 2)
        if contentWidth > 0, abs(contentWidth - renderedWidth) > 0.5 {
            renderedWidth = contentWidth
            if example == .markdownStreaming, let streamingDocument {
                example.apply(
                    document: streamingDocument,
                    to: richTextView,
                    constrainedWidth: contentWidth,
                    resolver: contentResolver
                )
            } else {
                example.apply(
                    to: richTextView,
                    constrainedWidth: contentWidth,
                    resolver: contentResolver
                )
            }
        }
        let noteHeight = noteLabel.sizeThatFits(
            CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        ).height
        noteLabel.frame = CGRect(x: horizontalInset, y: 24, width: contentWidth, height: noteHeight)

        let richTextY = noteLabel.frame.maxY + 24
        let richTextSize = richTextView.sizeThatFits(
            CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        )
        richTextView.frame = CGRect(
            x: horizontalInset,
            y: richTextY,
            width: contentWidth,
            height: richTextSize.height
        )
        scrollView.contentSize = CGSize(
            width: scrollView.bounds.width,
            height: richTextView.frame.maxY + 40
        )
        if needsStreamingScrollToBottom {
            needsStreamingScrollToBottom = false
            scrollToBottom()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        example.apply(
            to: richTextView,
            constrainedWidth: max(1, renderedWidth),
            resolver: contentResolver
        )
    }

    private func configureViews() {
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        view.addSubview(scrollView)

        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0
        noteLabel.text = example.note
        noteLabel.accessibilityIdentifier = "example.note"
        scrollView.addSubview(noteLabel)

        configureSelection()
        richTextView.actionHandler = { [weak self] _, identifier in
            self?.activate(identifier: identifier)
        }
        richTextView.accessibilityIdentifier = "example.content"
        scrollView.addSubview(richTextView)
    }

    private func activate(identifier: String) {
        guard identifier.hasPrefix("link:"),
              let url = URL(string: String(identifier.dropFirst("link:".count))) else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    private func configureSelection() {
        guard example.supportsSelection else { return }
        richTextView.initialSelectionPolicy = .currentLine
        richTextView.selectionMenuPresenter = selectionMenuPresenter
        richTextView.selectionMenuActions = { selection in
            [RichSelectionMenuAction(
                title: "Copy",
                image: UIImage(systemName: "doc.on.doc")
            ) {
                UIPasteboard.general.string = selection.plainText
            }]
        }
        richTextView.isTextSelectionEnabled = true
    }

    @objc private func restartTypewriter() {
        followsStreamingContent = true
        needsStreamingScrollToBottom = false
        streamingDocument = nil
        scrollView.setContentOffset(
            CGPoint(x: 0, y: -scrollView.adjustedContentInset.top),
            animated: false
        )
        markdownTypewriter.start()
    }

    private func applyTypewriterUpdate(_ update: ExampleMarkdownTypewriter.Update) {
        streamingDocument = update.document
        let snapshot = streamingRenderer.render(document: update.document,
            constrainedWidth: max(1, renderedWidth), configuration: ExampleCase.renderingConfiguration,
            resolver: contentResolver, streaming: !update.isComplete).snapshot
        let layout = streamingLayoutEngine.layout(snapshot: snapshot,
            constrainedTo: CGSize(width: max(1, renderedWidth), height: .greatestFiniteMagnitude))
        richTextView.displaysAsynchronously = true
        richTextView.animatesStreamingChanges = !update.isComplete
        richTextView.apply(snapshot, layout: layout)
        let progress = update.isComplete
            ? "Complete · \(update.totalUnitCount) characters"
            : "Typing · \(update.visibleUnitCount)/\(update.totalUnitCount) characters"
        noteLabel.text = "\(example.note)\n\n\(progress)"
        needsStreamingScrollToBottom = followsStreamingContent
        view.setNeedsLayout()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard example == .markdownStreaming else { return }
        followsStreamingContent = false
        needsStreamingScrollToBottom = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard example == .markdownStreaming,
              scrollView.isTracking || scrollView.isDecelerating else { return }
        followsStreamingContent = isNearBottom
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard example == .markdownStreaming, !decelerate else { return }
        followsStreamingContent = isNearBottom
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard example == .markdownStreaming else { return }
        followsStreamingContent = isNearBottom
    }

    private var isNearBottom: Bool {
        let visibleBottom = scrollView.contentOffset.y
            + scrollView.bounds.height
            - scrollView.adjustedContentInset.bottom
        return scrollView.contentSize.height - visibleBottom <= 72
    }

    private func scrollToBottom() {
        let minimumOffset = -scrollView.adjustedContentInset.top
        let maximumOffset = scrollView.contentSize.height
            - scrollView.bounds.height
            + scrollView.adjustedContentInset.bottom
        scrollView.setContentOffset(
            CGPoint(x: 0, y: max(minimumOffset, maximumOffset)),
            animated: false
        )
    }
}
