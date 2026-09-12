import UIKit

@MainActor
final class RichCodeBlockView: UIView {
    private let headerView = UIView()
    private let languageLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let dividerView = UIView()
    private let codeScrollView = UIScrollView()
    private let codeTextView = RichTextView()
    private var code = ""
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
        code: String,
        language: String?,
        backgroundColor: UIColor,
        contentInsets: RichContainerInsets,
        cornerRadius: CGFloat
    ) {
        self.backgroundColor = backgroundColor
        self.code = code
        self.contentInsets = contentInsets
        layer.cornerRadius = max(0, cornerRadius)
        let language = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        languageLabel.text = language.isEmpty
            ? nil
            : language.prefix(1).uppercased() + language.dropFirst()
        headerHeight = language.isEmpty ? 0 : 34
        headerView.isHidden = language.isEmpty
        codeTextView.attributedText = attributedCode
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        headerView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        languageLabel.frame = CGRect(x: 16, y: 0, width: max(0, bounds.width - 68), height: headerHeight)
        copyButton.frame = CGRect(x: max(0, bounds.width - 40), y: 4, width: 36, height: 26)
        dividerView.frame = CGRect(x: 0, y: max(0, headerHeight - 1), width: bounds.width, height: 1)
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

    private func configure() {
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor

        headerView.backgroundColor = .secondarySystemBackground
        addSubview(headerView)

        languageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        languageLabel.textColor = .label
        headerView.addSubview(languageLabel)

        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.tintColor = .secondaryLabel
        copyButton.addTarget(self, action: #selector(copyCode), for: .touchUpInside)
        headerView.addSubview(copyButton)

        dividerView.backgroundColor = .separator
        headerView.addSubview(dividerView)

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

    @objc private func copyCode() {
        UIPasteboard.general.string = code
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}

final class RichCodeBlockViewProvider: RichAttachmentViewProvider, @unchecked Sendable {
    static let reuseIdentifier = "RichTextView.CodeBlock"

    let requiredHeight: CGFloat
    private let attributedCode: NSAttributedString
    private let code: String
    private let language: String?
    private let backgroundColor: UIColor
    private let contentInsets: RichContainerInsets
    private let cornerRadius: CGFloat

    init(
        attributedCode: NSAttributedString,
        code: String,
        language: String?,
        backgroundColor: UIColor,
        contentInsets: RichContainerInsets,
        cornerRadius: CGFloat
    ) {
        self.attributedCode = NSAttributedString(attributedString: attributedCode)
        self.code = code
        self.language = language
        self.backgroundColor = backgroundColor
        self.contentInsets = contentInsets
        self.cornerRadius = cornerRadius
        requiredHeight = Self.requiredContentSize(
            for: attributedCode,
            contentInsets: contentInsets
        ).height + ((language?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 34 : 0)
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
            code: code,
            language: language,
            backgroundColor: backgroundColor,
            contentInsets: contentInsets,
            cornerRadius: cornerRadius
        )
    }

    @MainActor
    func prepareForReuse(_ view: UIView) {
        view.transform = .identity
    }

    static func requiredContentSize(
        for attributedCode: NSAttributedString,
        contentInsets: RichContainerInsets
    ) -> CGSize {
        let bounds = attributedCode.boundingRect(
            with: CGSize(width: 100_000, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return CGSize(
            width: ceil(bounds.width) + contentInsets.left + contentInsets.right,
            height: ceil(bounds.height) + contentInsets.top + contentInsets.bottom
        )
    }
}
