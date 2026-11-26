import UIKit

@MainActor
final class RichCodeBlockHeaderView: UIView {
    nonisolated static let height: CGFloat = 30

    nonisolated static func copyFrame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + max(0, bounds.width - 48), y: bounds.minY, width: min(44, bounds.width), height: height)
    }

    private lazy var languageLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        return label
    }()

    private lazy var copyIconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        let imageView = UIImageView(image: UIImage(systemName: "doc.on.doc", withConfiguration: configuration))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        return imageView
    }()

    private lazy var copyControl: UIControl = {
        let control = UIControl()
        control.accessibilityLabel = "Copy"
        control.accessibilityTraits = .button
        control.addAction(UIAction { [weak self] _ in
            guard let self, let host = enclosingRichTextView else { return }
            let point = CGPoint(x: copyControl.frame.midX, y: copyControl.frame.midY)
            var ancestor = superview
            while let view = ancestor, view !== host {
                if let canvas = view as? RichTableCanvas {
                    canvas.handleTap(at: convert(point, to: canvas))
                    return
                }
                ancestor = view.superview
            }
            host.handleContentTap(at: convert(point, to: host))
        }, for: .touchUpInside)
        control.addSubview(copyIconView)
        return control
    }()

    private lazy var dividerView: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        addSubview(languageLabel)
        addSubview(copyControl)
        addSubview(dividerView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(language: String) {
        languageLabel.text = language.prefix(1).uppercased() + language.dropFirst()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        languageLabel.frame = CGRect(x: 16, y: 0, width: max(0, bounds.width - 68), height: bounds.height)
        copyControl.frame = Self.copyFrame(in: bounds)
        copyIconView.frame = CGRect(x: 10, y: (bounds.height - 24) / 2, width: 24, height: 24)
        dividerView.frame = CGRect(x: 0, y: max(0, bounds.height - 1), width: bounds.width, height: 1)
    }

}

@MainActor
final class RichCodeBlockView: UIView {
    private let headerView = RichCodeBlockHeaderView()
    private let codeScrollView = UIScrollView()
    private let codeTextView = RichTextView()
    private var headerHeight: CGFloat = 0
    private var contentInsets = RichContainerInsets.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        attributedCode: NSAttributedString,
        language: String?,
        backgroundColor: UIColor,
        contentInsets: RichContainerInsets,
        cornerRadius: CGFloat
    ) {
        self.backgroundColor = backgroundColor
        self.contentInsets = contentInsets
        layer.cornerRadius = max(0, cornerRadius)
        let language = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        headerView.apply(language: language)
        headerHeight = language.isEmpty ? 0 : RichCodeBlockHeaderView.height
        headerView.isHidden = language.isEmpty
        codeTextView.attributedText = attributedCode
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        codeScrollView.frame = CGRect(
            x: contentInsets.left,
            y: headerHeight + contentInsets.top,
            width: max(0, bounds.width - contentInsets.left - contentInsets.right),
            height: max(0, bounds.height - headerHeight - contentInsets.top - contentInsets.bottom)
        )
        let naturalSize = codeTextView.sizeThatFits(
            CGSize(width: max(1, codeScrollView.bounds.width), height: 100_000)
        )
        let contentSize = CGSize(
            width: max(codeScrollView.bounds.width, naturalSize.width),
            height: codeScrollView.bounds.height
        )
        codeTextView.frame = CGRect(origin: .zero, size: contentSize)
        codeScrollView.contentSize = contentSize
    }

    func prepareForReuse() {
        codeTextView.prepareForReuse()
        codeScrollView.contentOffset = .zero
        transform = .identity
    }

    private func configure() {
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor

        addSubview(headerView)

        codeScrollView.showsHorizontalScrollIndicator = true
        codeScrollView.showsVerticalScrollIndicator = false
        codeScrollView.alwaysBounceHorizontal = false
        codeScrollView.alwaysBounceVertical = false
        codeScrollView.isDirectionalLockEnabled = true
        codeScrollView.contentInsetAdjustmentBehavior = .never
        addSubview(codeScrollView)

        codeTextView.backgroundColor = .clear
        codeTextView.laysOutAsynchronously = false
        codeTextView.displaysAsynchronously = false
        codeTextView.lineBreakMode = .byClipping
        codeScrollView.addSubview(codeTextView)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}

final class RichCodeBlockViewProvider: RichAttachmentViewProvider, @unchecked Sendable {
    static let reuseIdentifier = "RichTextView.CodeBlock"

    let copyAction: RichAction
    let copyElementID: String
    let requiredHeight: CGFloat
    private let attributedCode: NSAttributedString
    private let language: String?
    private let backgroundColor: UIColor
    private let contentInsets: RichContainerInsets
    private let cornerRadius: CGFloat

    init(
        nodeID: String,
        copyAction: RichAction,
        attributedCode: NSAttributedString,
        language: String?,
        backgroundColor: UIColor,
        contentInsets: RichContainerInsets,
        cornerRadius: CGFloat
    ) {
        self.copyAction = copyAction
        copyElementID = "\(nodeID)/copy"
        self.attributedCode = NSAttributedString(attributedString: attributedCode)
        self.language = language
        self.backgroundColor = backgroundColor
        self.contentInsets = contentInsets
        self.cornerRadius = cornerRadius
        requiredHeight = Self.requiredContentSize(
            for: attributedCode,
            contentInsets: contentInsets
        ).height + ((language?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? RichCodeBlockHeaderView.height : 0)
    }

    func copyRegion(in box: RichAttachmentRunBox) -> RichInteractiveRegion? {
        guard language?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return nil }
        return RichInteractiveRegion(
            action: copyAction, elementID: copyElementID, range: box.globalRange,
            rects: [RichCodeBlockHeaderView.copyFrame(in: box.contentFrame.integral)]
        )
    }

    @MainActor
    func makeView() -> UIView {
        RichCodeBlockView()
    }

    @MainActor
    func updateView(_ view: UIView) {
        guard let view = view as? RichCodeBlockView else { return }
        view.apply(
            attributedCode: attributedCode,
            language: language,
            backgroundColor: backgroundColor,
            contentInsets: contentInsets,
            cornerRadius: cornerRadius
        )
    }

    @MainActor
    func prepareForReuse(_ view: UIView) {
        (view as? RichCodeBlockView)?.prepareForReuse()
    }

    static func requiredContentSize(
        for attributedCode: NSAttributedString,
        contentInsets: RichContainerInsets
    ) -> CGSize {
        let size = RichCoreTextLayout(
            attributedText: attributedCode,
            constrainedWidth: 100_000,
            lineBreakMode: .byClipping
        )?.size ?? .zero
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }
}
