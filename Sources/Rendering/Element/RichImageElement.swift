import UIKit

public struct RichImageSource: Sendable {
    public let identifier: String
    public let image: UIImage?
    public let loadsRemotely: Bool

    public init(identifier: String, image: UIImage?, loadsRemotely: Bool = false) {
        self.identifier = identifier
        self.image = image
        self.loadsRemotely = loadsRemotely
    }
}

public final class RichAttributedInlineImage: @unchecked Sendable {
    public static let attributeName = NSAttributedString.Key(
        "io.github.felikslv01.rich-text-view.attributed-inline-image"
    )

    public let id: String
    public let source: RichImageSource
    public let size: CGSize
    public let contentInsets: UIEdgeInsets
    public let font: UIFont
    public let contentMode: UIView.ContentMode
    public let tintColor: UIColor?
    public let copyText: String?
    public let accessibilityLabel: String?
    public var actionIdentifier: String { action?.legacyIdentifier ?? "" }
    public let action: RichAction?

    public convenience init(
        id: String,
        source: RichImageSource,
        size: CGSize,
        contentInsets: UIEdgeInsets = .zero,
        font: UIFont,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        tintColor: UIColor? = nil,
        copyText: String? = nil,
        accessibilityLabel: String? = nil,
        actionIdentifier: String = ""
    ) {
        self.init(
            id: id,
            source: source,
            size: size,
            contentInsets: contentInsets,
            font: font,
            contentMode: contentMode,
            tintColor: tintColor,
            copyText: copyText,
            accessibilityLabel: accessibilityLabel,
            action: RichAction(legacyIdentifier: actionIdentifier)
        )
    }

    public init(
        id: String,
        source: RichImageSource,
        size: CGSize,
        contentInsets: UIEdgeInsets = .zero,
        font: UIFont,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        tintColor: UIColor? = nil,
        copyText: String? = nil,
        accessibilityLabel: String? = nil,
        action: RichAction?
    ) {
        self.id = id
        self.source = source
        self.size = size
        self.contentInsets = contentInsets
        self.font = font
        self.contentMode = contentMode
        self.tintColor = tintColor
        self.copyText = copyText
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var attributedString: NSAttributedString {
        NSAttributedString(
            string: "\u{FFFC}",
            attributes: [
                Self.attributeName: self,
                .font: font,
                .foregroundColor: UIColor.clear
            ]
        )
    }

    public func element(id: String? = nil) -> RichImageElement {
        element(id: id, action: action)
    }

    func element(id: String?, action: RichAction?) -> RichImageElement {
        RichImageElement(
            id: id ?? self.id,
            source: source,
            size: size,
            contentInsets: contentInsets,
            font: font,
            contentMode: contentMode,
            tintColor: tintColor,
            copyText: copyText,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }
}

@MainActor
public final class RichImageLoadTask {
    private var cancellation: (() -> Void)?

    public init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    public func cancel() {
        cancellation?()
        cancellation = nil
    }
}

@MainActor
public protocol RichImageLoader: AnyObject {
    func loadImage(
        for source: RichImageSource,
        completion: @escaping @MainActor (UIImage?) -> Void
    ) -> RichImageLoadTask?
}

public final class RichImageElement: RichElement, RichActionElement, @unchecked Sendable {
    let drawingID = UUID()
    public let source: RichImageSource
    public let size: CGSize
    public let contentInsets: UIEdgeInsets
    public let font: UIFont
    public let contentMode: UIView.ContentMode
    public let tintColor: UIColor?
    public let copyText: String?
    public let accessibilityLabel: String?
    var actionIdentifier: String { action?.legacyIdentifier ?? "" }
    public let action: RichAction?

    public convenience init(
        id: String,
        source: RichImageSource,
        size: CGSize,
        contentInsets: UIEdgeInsets = .zero,
        font: UIFont,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        tintColor: UIColor? = nil,
        copyText: String? = nil,
        accessibilityLabel: String? = nil,
        actionIdentifier: String = "",
        display: RichElementDisplay = .inline
    ) {
        self.init(
            id: id,
            source: source,
            size: size,
            contentInsets: contentInsets,
            font: font,
            contentMode: contentMode,
            tintColor: tintColor,
            copyText: copyText,
            accessibilityLabel: accessibilityLabel,
            action: RichAction(legacyIdentifier: actionIdentifier),
            display: display
        )
    }

    public init(
        id: String,
        source: RichImageSource,
        size: CGSize,
        contentInsets: UIEdgeInsets = .zero,
        font: UIFont,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        tintColor: UIColor? = nil,
        copyText: String? = nil,
        accessibilityLabel: String? = nil,
        action: RichAction?,
        display: RichElementDisplay = .inline
    ) {
        self.source = source
        self.size = size
        self.contentInsets = contentInsets
        self.font = font
        self.contentMode = contentMode
        self.tintColor = tintColor
        self.copyText = copyText
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        super.init(id: id, display: display)
    }
}
