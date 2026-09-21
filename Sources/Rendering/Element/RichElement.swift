import UIKit

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
    case background(color: UIColor, cornerRadius: CGFloat)
    case topRoundedBackground(color: UIColor, cornerRadius: CGFloat)
    case borderedBackground(color: UIColor, cornerRadius: CGFloat, borderColor: UIColor, borderWidth: CGFloat)
    case verticalGradient(topColor: UIColor, bottomColor: UIColor)
    case leadingRule(color: UIColor, width: CGFloat)
    case listMarker(attributedText: NSAttributedString, width: CGFloat)
    case horizontalRule(color: UIColor)
}

final class RichVerticalGradientElement: RichElement, @unchecked Sendable {
    let topColor: UIColor
    let bottomColor: UIColor
    let extent: CGFloat

    init(id: String, topColor: UIColor, bottomColor: UIColor, extent: CGFloat) {
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.extent = max(0, extent)
        super.init(id: id, display: .block)
    }
}

open class RichElement: @unchecked Sendable {
    public let id: String
    public let display: RichElementDisplay

    open var children: [RichElement] { [] }

    public init(
        id: String,
        display: RichElementDisplay
    ) {
        precondition(!id.isEmpty, "RichElement ID must not be empty")
        self.id = id
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
        decoration: RichContainerDecoration? = nil
    ) {
        storedChildren = children
        self.spacing = spacing
        self.contentInsets = contentInsets
        self.decoration = decoration
        super.init(id: id, display: display)
    }

    public override func replacingChildren(_ children: [RichElement]) -> RichElement {
        RichContainerElement(
            id: id,
            children: children,
            display: display,
            spacing: spacing,
            contentInsets: contentInsets,
            decoration: decoration
        )
    }
}

public final class RichBreakElement: RichElement, @unchecked Sendable {
    public let extent: CGFloat

    public init(
        id: String,
        extent: CGFloat = 0,
        display: RichElementDisplay = .block
    ) {
        self.extent = extent
        super.init(id: id, display: display)
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
        extent: CGFloat = 9
    ) {
        self.color = color
        self.lineHeight = max(0, lineHeight)
        self.extent = max(lineHeight, extent)
        super.init(id: id, display: .block)
    }
}
