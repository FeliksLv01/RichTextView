import UIKit

public class RichTextElement: RichElement, @unchecked Sendable {
    public let attributedText: NSAttributedString
    public let copyText: String
    public let maximumNumberOfLines: Int
    public let lineBreakMode: NSLineBreakMode

    public init(
        id: String,
        attributedText: NSAttributedString,
        copyText: String? = nil,
        maximumNumberOfLines: Int = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        display: RichElementDisplay = .inline
    ) {
        self.attributedText = attributedText.copy() as! NSAttributedString
        self.copyText = copyText ?? attributedText.string
        self.maximumNumberOfLines = max(0, maximumNumberOfLines)
        self.lineBreakMode = lineBreakMode
        super.init(id: id, display: display)
    }
}

protocol RichActionElement {
    var action: RichAction? { get }
}

public final class RichAnchorElement: RichTextElement, RichActionElement, @unchecked Sendable {
    public var actionIdentifier: String { action?.legacyIdentifier ?? "" }
    public let action: RichAction?

    public convenience init(
        id: String,
        attributedText: NSAttributedString,
        actionIdentifier: String,
        copyText: String? = nil,
        maximumNumberOfLines: Int = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        display: RichElementDisplay = .inline
    ) {
        self.init(
            id: id,
            attributedText: attributedText,
            action: RichAction(legacyIdentifier: actionIdentifier),
            copyText: copyText,
            maximumNumberOfLines: maximumNumberOfLines,
            lineBreakMode: lineBreakMode,
            display: display
        )
    }

    public init(
        id: String,
        attributedText: NSAttributedString,
        action: RichAction?,
        copyText: String? = nil,
        maximumNumberOfLines: Int = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        display: RichElementDisplay = .inline
    ) {
        self.action = action
        super.init(
            id: id,
            attributedText: attributedText,
            copyText: copyText,
            maximumNumberOfLines: maximumNumberOfLines,
            lineBreakMode: lineBreakMode,
            display: display
        )
    }
}

public final class RichTextBadgeElement: RichElement, RichActionElement, @unchecked Sendable {
    public let attributedText: NSAttributedString
    public let contentInsets: UIEdgeInsets
    public let outerInsets: UIEdgeInsets
    public let cornerRadius: CGFloat
    public let borderColor: UIColor?
    public let borderWidth: CGFloat
    public let baselineOffset: CGFloat
    public var actionIdentifier: String { action?.legacyIdentifier ?? "" }
    public let action: RichAction?
    public let copyText: String

    public convenience init(
        id: String,
        text: String,
        font: UIFont,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        contentInsets: UIEdgeInsets,
        outerInsets: UIEdgeInsets = .zero,
        cornerRadius: CGFloat,
        borderColor: UIColor? = nil,
        borderWidth: CGFloat = 0,
        baselineOffset: CGFloat = 0,
        actionIdentifier: String,
        copyText: String? = nil
    ) {
        self.init(
            id: id,
            text: text,
            font: font,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            contentInsets: contentInsets,
            outerInsets: outerInsets,
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            borderWidth: borderWidth,
            baselineOffset: baselineOffset,
            action: RichAction(legacyIdentifier: actionIdentifier),
            copyText: copyText
        )
    }

    public convenience init(
        id: String,
        text: String,
        font: UIFont,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        contentInsets: UIEdgeInsets,
        outerInsets: UIEdgeInsets = .zero,
        cornerRadius: CGFloat,
        borderColor: UIColor? = nil,
        borderWidth: CGFloat = 0,
        baselineOffset: CGFloat = 0,
        action: RichAction?,
        copyText: String? = nil
    ) {
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: foregroundColor,
                .backgroundColor: backgroundColor
            ]
        )
        self.init(
            id: id,
            attributedText: attributedText,
            contentInsets: contentInsets,
            outerInsets: outerInsets,
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            borderWidth: borderWidth,
            baselineOffset: baselineOffset,
            action: action,
            copyText: copyText
        )
    }

    public convenience init(
        id: String,
        attributedText: NSAttributedString,
        contentInsets: UIEdgeInsets,
        outerInsets: UIEdgeInsets = .zero,
        cornerRadius: CGFloat,
        borderColor: UIColor? = nil,
        borderWidth: CGFloat = 0,
        baselineOffset: CGFloat = 0,
        actionIdentifier: String = "",
        copyText: String? = nil
    ) {
        self.init(
            id: id,
            attributedText: attributedText,
            contentInsets: contentInsets,
            outerInsets: outerInsets,
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            borderWidth: borderWidth,
            baselineOffset: baselineOffset,
            action: RichAction(legacyIdentifier: actionIdentifier),
            copyText: copyText
        )
    }

    public init(
        id: String,
        attributedText: NSAttributedString,
        contentInsets: UIEdgeInsets,
        outerInsets: UIEdgeInsets = .zero,
        cornerRadius: CGFloat,
        borderColor: UIColor? = nil,
        borderWidth: CGFloat = 0,
        baselineOffset: CGFloat = 0,
        action: RichAction?,
        copyText: String? = nil
    ) {
        self.contentInsets = contentInsets
        self.outerInsets = outerInsets
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.borderWidth = max(0, borderWidth)
        self.baselineOffset = baselineOffset
        self.action = action
        self.copyText = copyText ?? attributedText.string
        self.attributedText = NSAttributedString(attributedString: attributedText)
        super.init(id: id, display: .inline)
    }
}
