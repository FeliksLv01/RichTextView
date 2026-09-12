import UIKit

public struct RichCodeHighlightTokenStyle {
    public let foregroundColor: UIColor?
    public let backgroundColor: UIColor?
    public let font: UIFont?

    public init(
        foregroundColor: UIColor? = nil,
        backgroundColor: UIColor? = nil,
        font: UIFont? = nil
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.font = font
    }
}

public struct RichCodeHighlightTheme {
    public let font: UIFont
    public let lineHeight: CGFloat
    public let textColor: UIColor
    public let backgroundColor: UIColor
    public let codeBlockInsets: UIEdgeInsets
    public let codeBlockCornerRadius: CGFloat
    public let tokenStyles: [String: RichCodeHighlightTokenStyle]

    public init(
        font: UIFont,
        lineHeight: CGFloat,
        textColor: UIColor,
        backgroundColor: UIColor,
        codeBlockInsets: UIEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16),
        codeBlockCornerRadius: CGFloat = 8,
        tokenStyles: [String: RichCodeHighlightTokenStyle]
    ) {
        self.font = font
        self.lineHeight = lineHeight
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.codeBlockInsets = codeBlockInsets
        self.codeBlockCornerRadius = codeBlockCornerRadius
        self.tokenStyles = tokenStyles
    }

    func style(for capture: String) -> RichCodeHighlightTokenStyle? {
        var components = capture.split(separator: ".")
        while !components.isEmpty {
            if let style = tokenStyles[components.joined(separator: ".")] {
                return style
            }
            components.removeLast()
        }
        return nil
    }

    public static var `default`: Self { .github }

    public static var github: Self {
        builtIn(
            background: dynamic(light: 0xF6F8FA, dark: 0x161B22),
            text: dynamic(light: 0x24292F, dark: 0xC9D1D9),
            keyword: dynamic(light: 0xCF222E, dark: 0xFF7B72),
            type: dynamic(light: 0x953800, dark: 0xFFA657),
            string: dynamic(light: 0x0A3069, dark: 0xA5D6FF),
            comment: dynamic(light: 0x6E7781, dark: 0x8B949E),
            number: dynamic(light: 0x0550AE, dark: 0x79C0FF),
            function: dynamic(light: 0x8250DF, dark: 0xD2A8FF),
            property: dynamic(light: 0x0550AE, dark: 0x79C0FF),
            accent: dynamic(light: 0x116329, dark: 0x7EE787)
        )
    }

    public static var xcode: Self {
        builtIn(
            background: dynamic(light: 0xFFFFFF, dark: 0x1F1F24),
            text: dynamic(light: 0x000000, dark: 0xFFFFFF),
            keyword: dynamic(light: 0x9B2393, dark: 0xFC5FA3),
            type: dynamic(light: 0x0B4F79, dark: 0x5DD8FF),
            string: dynamic(light: 0xC41A16, dark: 0xFC6A5D),
            comment: dynamic(light: 0x267507, dark: 0x6C7986),
            number: dynamic(light: 0x1C00CF, dark: 0xD0BF69),
            function: dynamic(light: 0x326D74, dark: 0x67B7A4),
            property: dynamic(light: 0x326D74, dark: 0x67B7A4),
            accent: dynamic(light: 0x703DAA, dark: 0xA167E6)
        )
    }

    public static var monokai: Self {
        builtIn(
            background: color(0x272822), text: color(0xF8F8F2),
            keyword: color(0xF92672), type: color(0x66D9EF),
            string: color(0xE6DB74), comment: color(0x75715E),
            number: color(0xAE81FF), function: color(0xA6E22E),
            property: color(0x66D9EF), accent: color(0xFD971F)
        )
    }

    public static var dracula: Self {
        builtIn(
            background: color(0x282A36), text: color(0xF8F8F2),
            keyword: color(0xFF79C6), type: color(0x8BE9FD),
            string: color(0xF1FA8C), comment: color(0x6272A4),
            number: color(0xBD93F9), function: color(0x50FA7B),
            property: color(0x8BE9FD), accent: color(0xFFB86C)
        )
    }

    public static func preset(_ preset: RichCodeHighlightThemePreset) -> Self {
        switch preset {
        case .github: .github
        case .xcode: .xcode
        case .monokai: .monokai
        case .dracula: .dracula
        }
    }

    private static func builtIn(
        background: UIColor,
        text: UIColor,
        keyword: UIColor,
        type: UIColor,
        string: UIColor,
        comment: UIColor,
        number: UIColor,
        function: UIColor,
        property: UIColor,
        accent: UIColor
    ) -> Self {
        let regular = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let bold = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        return Self(
            font: regular,
            lineHeight: 22,
            textColor: text,
            backgroundColor: background,
            tokenStyles: [
                "attribute": .init(foregroundColor: accent),
                "boolean": .init(foregroundColor: number),
                "comment": .init(foregroundColor: comment),
                "constant": .init(foregroundColor: number),
                "constructor": .init(foregroundColor: type),
                "function": .init(foregroundColor: function),
                "keyword": .init(foregroundColor: keyword, font: bold),
                "label": .init(foregroundColor: accent),
                "number": .init(foregroundColor: number),
                "operator": .init(foregroundColor: keyword),
                "property": .init(foregroundColor: property),
                "punctuation": .init(foregroundColor: text),
                "string": .init(foregroundColor: string),
                "string.escape": .init(foregroundColor: accent),
                "type": .init(foregroundColor: type),
                "variable.builtin": .init(foregroundColor: accent),
                "variable.parameter": .init(foregroundColor: text)
            ]
        )
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in color(traits.userInterfaceStyle == .dark ? dark : light) }
    }

    private static func color(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }
}

public enum RichCodeHighlightThemePreset: String, CaseIterable, Sendable {
    case github
    case xcode
    case monokai
    case dracula
}
