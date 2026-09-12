import UIKit

public enum RichVerticalAlignment: Sendable {
    case top
    case center
    case bottom
    case baseline
}

public struct RichAttachmentMetrics: Equatable, Sendable {
    public let size: CGSize
    public let padding: UIEdgeInsets
    public let verticalAlignment: RichVerticalAlignment

    public init(
        size: CGSize,
        padding: UIEdgeInsets = .zero,
        verticalAlignment: RichVerticalAlignment = .center
    ) {
        self.size = size
        self.padding = padding
        self.verticalAlignment = verticalAlignment
    }

    public var occupiedSize: CGSize {
        CGSize(
            width: size.width + padding.left + padding.right,
            height: size.height + padding.top + padding.bottom
        )
    }
}

public protocol RichAttachmentViewProvider: AnyObject {
    @MainActor
    func makeView() -> UIView
    @MainActor
    func updateView(_ view: UIView)
    @MainActor
    func prepareForReuse(_ view: UIView)
}

public extension RichAttachmentViewProvider {
    @MainActor
    func prepareForReuse(_ view: UIView) {}
}

public final class RichAttachmentElement: RichElement, @unchecked Sendable {
    public let metrics: RichAttachmentMetrics
    public let font: UIFont?
    public let reuseIdentifier: String
    public let provider: any RichAttachmentViewProvider
    public let copyText: String?
    public let isSelectable: Bool

    public init(
        id: String,
        metrics: RichAttachmentMetrics,
        font: UIFont? = nil,
        reuseIdentifier: String,
        provider: any RichAttachmentViewProvider,
        copyText: String? = nil,
        isSelectable: Bool = false,
        display: RichElementDisplay = .block,
        revision: RichElementRevision = .initial
    ) {
        precondition(!reuseIdentifier.isEmpty, "Attachment reuse identifier must not be empty")
        self.metrics = metrics
        self.font = font
        self.reuseIdentifier = reuseIdentifier
        self.provider = provider
        self.copyText = copyText
        self.isSelectable = isSelectable
        super.init(id: id, revision: revision, display: display)
    }
}
