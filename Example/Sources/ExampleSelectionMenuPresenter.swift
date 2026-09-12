import RichTextView
import UIKit

@MainActor
final class ExampleSelectionMenuPresenter: RichSelectionMenuPresenting {
    private var overlayView: ExampleSelectionMenuOverlayView?

    func presentCopyMenu(
        from richView: RichTextView,
        sourceRect: CGRect,
        copy: @escaping () -> Void,
        selectionDidEnd: @escaping () -> Void
    ) {
        presentSelectionMenu(
            from: richView,
            sourceRect: sourceRect,
            actions: [RichSelectionMenuAction(
                title: "Copy",
                image: UIImage(systemName: "doc.on.doc"),
                perform: copy
            )],
            selectionDidEnd: selectionDidEnd
        )
    }

    func presentSelectionMenu(
        from richView: RichTextView,
        sourceRect: CGRect,
        actions: [RichSelectionMenuAction],
        selectionDidEnd: @escaping () -> Void
    ) {
        dismissMenu()
        guard !actions.isEmpty else { return }
        guard let window = richView.window else {
            selectionDidEnd()
            return
        }

        let overlayView = ExampleSelectionMenuOverlayView(
            frame: window.bounds,
            actions: actions,
            shouldPassThrough: { [weak richView] point in
                richView?.isSelectionHandleTouch(atWindowPoint: point) == true
            },
            perform: { [weak self] action in
                action.perform()
                self?.dismissMenu()
                selectionDidEnd()
            },
            dismiss: { [weak self] in
                self?.dismissMenu()
                selectionDidEnd()
            }
        )
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlayView)
        overlayView.present(from: richView.convert(sourceRect, to: window))
        self.overlayView = overlayView
    }

    func dismissCopyMenu(from richView: RichTextView) {
        dismissMenu()
    }

    private func dismissMenu() {
        overlayView?.removeFromSuperview()
        overlayView = nil
    }
}

private final class ExampleSelectionMenuOverlayView: UIView {
    private let shouldPassThrough: (CGPoint) -> Bool
    private let dismiss: () -> Void

    private lazy var menuView: UIStackView = {
        let view = UIStackView()
        view.axis = .horizontal
        view.alignment = .fill
        view.distribution = .fillEqually
        view.backgroundColor = UIColor(white: 0.16, alpha: 1)
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.accessibilityIdentifier = "example.selectionMenu"
        return view
    }()

    init(
        frame: CGRect,
        actions: [RichSelectionMenuAction],
        shouldPassThrough: @escaping (CGPoint) -> Bool,
        perform: @escaping (RichSelectionMenuAction) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.shouldPassThrough = shouldPassThrough
        self.dismiss = dismiss
        super.init(frame: frame)

        backgroundColor = .clear
        addSubview(menuView)
        actions.forEach { action in
            menuView.addArrangedSubview(ExampleSelectionMenuButton(action: action, perform: perform))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if menuView.frame.contains(point) {
            return super.hitTest(point, with: event)
        }
        let windowPoint = convert(point, to: window)
        return shouldPassThrough(windowPoint) ? nil : self
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        dismiss()
    }

    func present(from sourceRect: CGRect) {
        let itemWidth: CGFloat = 64
        let menuHeight: CGFloat = 64
        let horizontalInset: CGFloat = 16
        let verticalSpacing: CGFloat = 10
        let menuWidth = CGFloat(menuView.arrangedSubviews.count) * itemWidth
        let centerX = min(
            max(sourceRect.midX, horizontalInset + menuWidth / 2),
            bounds.width - horizontalInset - menuWidth / 2
        )
        let safeTop = safeAreaInsets.top + verticalSpacing
        let proposedTop = sourceRect.minY - menuHeight - verticalSpacing
        let top = proposedTop >= safeTop
            ? proposedTop
            : min(sourceRect.maxY + verticalSpacing, bounds.height - safeAreaInsets.bottom - menuHeight)
        menuView.frame = CGRect(
            x: centerX - menuWidth / 2,
            y: top,
            width: menuWidth,
            height: menuHeight
        )
    }

}

private final class ExampleSelectionMenuButton: UIButton {
    private let action: RichSelectionMenuAction
    private let perform: (RichSelectionMenuAction) -> Void

    init(action: RichSelectionMenuAction, perform: @escaping (RichSelectionMenuAction) -> Void) {
        self.action = action
        self.perform = perform
        super.init(frame: .zero)

        var configuration = UIButton.Configuration.plain()
        configuration.image = action.image?.withRenderingMode(.alwaysTemplate)
        configuration.imagePlacement = .top
        configuration.imagePadding = 6
        configuration.title = action.title
        configuration.baseForegroundColor = .white
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .caption1)
            return attributes
        }
        self.configuration = configuration
        accessibilityIdentifier = "example.selectionMenu.\(action.title.lowercased())"
        addTarget(self, action: #selector(performAction), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    @objc private func performAction() {
        perform(action)
    }
}
