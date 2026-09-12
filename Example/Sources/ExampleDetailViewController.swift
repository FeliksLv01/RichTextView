import RichTextView
import UIKit

final class ExampleDetailViewController: UIViewController {
    private let example: ExampleCase
    private let scrollView = UIScrollView()
    private let noteLabel = UILabel()
    private let imageLoader = ExampleRemoteImageLoader()
    private let selectionMenuPresenter = ExampleSelectionMenuPresenter()
    private lazy var richTextView = RichTextView(imageLoader: imageLoader)

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
        example.apply(to: richTextView, constrainedWidth: 320)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds

        let horizontalInset: CGFloat = 20
        let contentWidth = max(0, scrollView.bounds.width - horizontalInset * 2)
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
    }

    private func configureViews() {
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0
        noteLabel.text = example.note
        noteLabel.accessibilityIdentifier = "example.note"
        scrollView.addSubview(noteLabel)

        configureSelection()
        richTextView.accessibilityIdentifier = "example.content"
        scrollView.addSubview(richTextView)
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
}
