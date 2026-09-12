import UIKit

public struct RichElementRevision: Hashable, Sendable {
    public let layout: Int
    public let display: Int

    public init(layout: Int, display: Int) {
        self.layout = layout
        self.display = display
    }

    public static let initial = RichElementRevision(layout: 0, display: 0)
}

public enum RichElementDisplay: Sendable {
    case inline
    case block
}

public struct RichContainerInsets: Hashable, Sendable {
    public let top: CGFloat
    public let left: CGFloat
    public let bottom: CGFloat
    public let right: CGFloat

    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = RichContainerInsets()
}

public enum RichContainerDecoration: @unchecked Sendable {
    case leadingRule(color: UIColor, width: CGFloat)
    case listMarker(attributedText: NSAttributedString, width: CGFloat)
    case horizontalRule(color: UIColor)
}

open class RichElement: @unchecked Sendable {
    public let id: String
    public let revision: RichElementRevision
    public let display: RichElementDisplay

    open var children: [RichElement] { [] }

    public init(
        id: String,
        revision: RichElementRevision = .initial,
        display: RichElementDisplay
    ) {
        precondition(!id.isEmpty, "RichElement ID must not be empty")
        self.id = id
        self.revision = revision
        self.display = display
    }

    open func replacingChildren(_ children: [RichElement]) -> RichElement {
        precondition(children.isEmpty, "Leaf elements cannot accept children")
        return self
    }
}

public final class RichContainerElement: RichElement, @unchecked Sendable {
    private let storedChildren: [RichElement]
    public override var children: [RichElement] { storedChildren }
    public let spacing: CGFloat
    public let contentInsets: RichContainerInsets
    public let decoration: RichContainerDecoration?

    public init(
        id: String,
        children: [RichElement],
        display: RichElementDisplay = .block,
        spacing: CGFloat = 0,
        contentInsets: RichContainerInsets = .zero,
        decoration: RichContainerDecoration? = nil,
        revision: RichElementRevision = .initial
    ) {
        storedChildren = children
        self.spacing = spacing
        self.contentInsets = contentInsets
        self.decoration = decoration
        super.init(id: id, revision: revision, display: display)
    }

    public override func replacingChildren(_ children: [RichElement]) -> RichElement {
        RichContainerElement(
            id: id,
            children: children,
            display: display,
            spacing: spacing,
            contentInsets: contentInsets,
            decoration: decoration,
            revision: revision
        )
    }
}

public final class RichBreakElement: RichElement, @unchecked Sendable {
    public let extent: CGFloat

    public init(
        id: String,
        extent: CGFloat = 0,
        display: RichElementDisplay = .block,
        revision: RichElementRevision = .initial
    ) {
        self.extent = extent
        super.init(id: id, revision: revision, display: display)
    }
}

public final class RichDividerElement: RichElement, @unchecked Sendable {
    public let color: UIColor
    public let lineHeight: CGFloat
    public let extent: CGFloat

    public init(
        id: String,
        color: UIColor,
        lineHeight: CGFloat = 1,
        extent: CGFloat = 9,
        revision: RichElementRevision = .initial
    ) {
        self.color = color
        self.lineHeight = max(0, lineHeight)
        self.extent = max(lineHeight, extent)
        super.init(id: id, revision: revision, display: .block)
    }
}
