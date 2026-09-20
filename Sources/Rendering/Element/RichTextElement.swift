import UIKit

extension NSAttributedString {
    var richViewFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(string)
        enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, range, _ in
            hasher.combine(range.location)
            hasher.combine(range.length)
            for key in attributes.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                hasher.combine(key.rawValue)
                hasher.combine(String(reflecting: attributes[key]))
            }
        }
        return hasher.finalize()
    }
}

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
        self.attributedText = NSAttributedString(attributedString: attributedText)
        self.copyText = copyText ?? attributedText.string
        self.maximumNumberOfLines = max(0, maximumNumberOfLines)
        self.lineBreakMode = lineBreakMode
        super.init(id: id, display: display)
    }
}

protocol RichActionElement {
    var actionIdentifier: String { get }
}

public final class RichAnchorElement: RichTextElement, RichActionElement, @unchecked Sendable {
    public let actionIdentifier: String

    public init(
        id: String,
        attributedText: NSAttributedString,
        actionIdentifier: String,
        copyText: String? = nil,
        maximumNumberOfLines: Int = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        display: RichElementDisplay = .inline
    ) {
        self.actionIdentifier = actionIdentifier
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
    public let actionIdentifier: String
    public let copyText: String

    public init(
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
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: foregroundColor,
                .backgroundColor: backgroundColor
            ]
        )
        self.contentInsets = contentInsets
        self.outerInsets = outerInsets
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.borderWidth = max(0, borderWidth)
        self.baselineOffset = baselineOffset
        self.actionIdentifier = actionIdentifier
        self.copyText = copyText ?? text
        self.attributedText = attributedText
        super.init(id: id, display: .inline)
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
        actionIdentifier: String = "",
        copyText: String? = nil
    ) {
        self.contentInsets = contentInsets
        self.outerInsets = outerInsets
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.borderWidth = max(0, borderWidth)
        self.baselineOffset = baselineOffset
        self.actionIdentifier = actionIdentifier
        self.copyText = copyText ?? attributedText.string
        self.attributedText = NSAttributedString(attributedString: attributedText)
        super.init(id: id, display: .inline)
    }
}
