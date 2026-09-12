import Highlighter
import UIKit

final class ExampleCodeHighlighter {
    private let highlighter = Highlighter()

    func highlight(code: String, language: String) -> NSAttributedString {
        let theme = UITraitCollection.current.userInterfaceStyle == .dark
            ? "default-dark"
            : "default-light"
        highlighter?.setTheme(theme, withFont: "Courier", ofSize: 14)
        let highlighted = NSMutableAttributedString(
            attributedString: highlighter?.highlight(
                code,
                as: language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            ) ?? NSAttributedString(string: code)
        )
        let range = NSRange(location: 0, length: highlighted.length)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 22
        paragraphStyle.maximumLineHeight = 22
        paragraphStyle.lineBreakMode = .byClipping
        highlighted.enumerateAttribute(.font, in: range) { value, attributeRange, _ in
            let weight: UIFont.Weight
            if let font = value as? UIFont, font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                weight = .bold
            } else {
                weight = .regular
            }
            highlighted.addAttribute(
                .font,
                value: UIFont.monospacedSystemFont(ofSize: 14, weight: weight),
                range: attributeRange
            )
        }
        highlighted.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        return highlighted
    }
}
