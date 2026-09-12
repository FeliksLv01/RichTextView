import UIKit

public final class RichTextElementBuilder: RichContentElementBuilding {
    public let nodeType = RichContentNodeType.text
    public init() {}

    public func build(node: RichContentNode, children: [RichElement], context: RichContentRenderContext) -> RichElement? {
        guard let content = node.content(as: RichTextContent.self) else { return nil }
        let explicitForegroundColor = UIColor.richContentColor(content.style.foregroundColor)
        let explicitBackgroundColor = UIColor.richContentColor(content.style.backgroundColor)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: displayFont(
                baseFont: content.style.code
                    ? context.configuration.inlineCodeFont
                    : context.configuration.font,
                style: content.style
            ),
            .foregroundColor: context.configuration.textForegroundColorResolver?(
            explicitForegroundColor,
            explicitBackgroundColor,
            context.configuration.textColor,
            context.configuration.contrastBackgroundColor
            ) ?? explicitForegroundColor ?? context.configuration.textColor,
            .paragraphStyle: richParagraphStyle(context.configuration)
        ]
        attributes[.backgroundColor] = explicitBackgroundColor
            ?? (content.style.code ? context.configuration.codeBackgroundColor : nil)
        if content.style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if content.style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let text = NSMutableAttributedString(string: content.text, attributes: attributes)
        applyHighlights(to: text, tokens: context.configuration.highlightTokens, configuration: context.configuration)
        if content.style.code {
            return RichTextBadgeElement(
                id: node.id,
                attributedText: text,
                contentInsets: context.configuration.inlineCodeInsets,
                cornerRadius: context.configuration.inlineCodeCornerRadius,
                borderColor: context.configuration.inlineCodeBorderColor,
                borderWidth: context.configuration.inlineCodeBorderWidth,
                baselineOffset: context.configuration.inlineCodeBaselineOffset,
                actionIdentifier: "",
                revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
            )
        }
        return RichTextElement(
            id: node.id,
            attributedText: text,
            revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
        )
    }

    private func displayFont(baseFont: UIFont, style: RichTextStyle) -> UIFont {
        let pointSize = baseFont.pointSize * CGFloat(style.fontScale)
        let font: UIFont
        if style.code {
            let codeFont = baseFont.withSize(pointSize)
            font = style.bold
                ? UIFont.systemFont(ofSize: codeFont.pointSize, weight: .semibold)
                : codeFont
        } else if style.bold {
            font = UIFont.systemFont(ofSize: pointSize, weight: .bold)
        } else {
            font = UIFont(descriptor: baseFont.fontDescriptor, size: pointSize)
        }
        guard style.italic else { return font }
        return UIFont(
            descriptor: font.fontDescriptor.withMatrix(CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)),
            size: font.pointSize
        )
    }

    private func applyHighlights(
        to text: NSMutableAttributedString,
        tokens: [String],
        configuration: RichContentRenderingConfiguration
    ) {
        let source = text.string
        for token in tokens.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            var searchRange = source.startIndex..<source.endIndex
            while let range = source.range(of: token, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                text.addAttributes(
                    [
                        .foregroundColor: configuration.highlightTextColor,
                        .backgroundColor: configuration.highlightBackgroundColor
                    ],
                    range: NSRange(range, in: source)
                )
                searchRange = range.upperBound..<source.endIndex
            }
        }
    }
}

func richParagraphStyle(_ configuration: RichContentRenderingConfiguration) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = configuration.lineHeight
    style.maximumLineHeight = configuration.lineHeight
    return style
}

private extension UIColor {
    static func richContentColor(_ rawValue: String?) -> UIColor? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return richContentHexColor(value)
            ?? richContentCSSColor(value)
            ?? richContentNamedColor(value)
    }

    private static func richContentHexColor(_ value: String) -> UIColor? {
        var value = value
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8,
              let number = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let red = CGFloat((number >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = CGFloat((number >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = CGFloat((number >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? CGFloat(number & 0xFF) / 255 : 1
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func richContentCSSColor(_ value: String) -> UIColor? {
        let value = value.lowercased()
        guard value.hasPrefix("rgb(") || value.hasPrefix("rgba("),
              value.hasSuffix(")"),
              let openParenIndex = value.firstIndex(of: "(") else { return nil }
        let bodyStart = value.index(after: openParenIndex)
        let body = value[bodyStart..<value.index(before: value.endIndex)]
        let components = body.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard components.count == 3 || components.count == 4,
              let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2]),
              (0...255).contains(red),
              (0...255).contains(green),
              (0...255).contains(blue) else { return nil }
        let alpha = components.count == 4
            ? min(max(Double(components[3]) ?? 1, 0), 1)
            : 1
        return UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha)
        )
    }

    private static func richContentNamedColor(_ value: String) -> UIColor? {
        switch value.lowercased() {
        case "label": UIColor.label
        case "secondarylabel": UIColor.secondaryLabel
        case "systemblue": UIColor.systemBlue
        case "systemgreen": UIColor.systemGreen
        case "systemorange": UIColor.systemOrange
        case "systemred": UIColor.systemRed
        case "systemyellow": UIColor.systemYellow
        case "secondarysystemfill": UIColor.secondarySystemFill
        case "secondarysystembackground": UIColor.secondarySystemBackground
        case "black": UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        case "white": UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        case "red": UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        case "green": UIColor(red: 0, green: 128.0 / 255, blue: 0, alpha: 1)
        case "blue": UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        case "gray", "grey": UIColor(red: 128.0 / 255, green: 128.0 / 255, blue: 128.0 / 255, alpha: 1)
        case "yellow": UIColor(red: 1, green: 1, blue: 0, alpha: 1)
        case "transparent": UIColor(red: 0, green: 0, blue: 0, alpha: 0)
        default: nil
        }
    }
}
