import UIKit

public struct RichContentLayoutMetrics: Sendable {
    public let blockSpacing: CGFloat
    public let listIndent: CGFloat
    public let blockQuoteIndicatorWidth: CGFloat
    public let blockQuoteContentSpacing: CGFloat

    public init(
        blockSpacing: CGFloat = 8,
        listIndent: CGFloat = 24,
        blockQuoteIndicatorWidth: CGFloat = 2,
        blockQuoteContentSpacing: CGFloat = 8
    ) {
        self.blockSpacing = blockSpacing
        self.listIndent = listIndent
        self.blockQuoteIndicatorWidth = blockQuoteIndicatorWidth
        self.blockQuoteContentSpacing = blockQuoteContentSpacing
    }
}

public struct RichContentResolvedLink: Sendable {
    public let title: String?
    public let icon: String?

    public init(title: String? = nil, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }
}

public struct RichMentionPresentation {
    public let displayText: String
    public let isHighlighted: Bool
    public let foregroundColor: UIColor?
    public let trailingElement: RichElement?

    public init(
        displayText: String,
        isHighlighted: Bool,
        foregroundColor: UIColor? = nil,
        trailingElement: RichElement? = nil
    ) {
        self.displayText = displayText
        self.isHighlighted = isHighlighted
        self.foregroundColor = foregroundColor
        self.trailingElement = trailingElement
    }
}

public struct RichInlineImagePresentation {
    public let source: RichImageSource
    public let size: CGSize
    public let contentInsets: UIEdgeInsets
    public let copyText: String?
    public let accessibilityLabel: String?

    public init(
        source: RichImageSource,
        size: CGSize,
        contentInsets: UIEdgeInsets = .zero,
        copyText: String? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.source = source
        self.size = size
        self.contentInsets = contentInsets
        self.copyText = copyText
        self.accessibilityLabel = accessibilityLabel
    }
}

public protocol RichContentPresentationResolving: AnyObject {
    func overrideElement(for node: RichContentNode, context: RichContentRenderContext) -> RichElement?
    func mentionPresentation(for node: RichContentNode, content: RichMentionContent) -> RichMentionPresentation?
    func emojiPresentation(for node: RichContentNode, content: RichEmojiContent) -> RichInlineImagePresentation?
    func imagePresentation(for node: RichContentNode, content: RichImageContent) -> RichInlineImagePresentation?
    func linkIconPresentation(for node: RichContentNode, content: RichLinkContent) -> RichInlineImagePresentation?
    func resolvedLink(for node: RichContentNode, content: RichLinkContent) -> RichContentResolvedLink?
}

public extension RichContentPresentationResolving {
    func overrideElement(for node: RichContentNode, context: RichContentRenderContext) -> RichElement? { nil }
    func mentionPresentation(for node: RichContentNode, content: RichMentionContent) -> RichMentionPresentation? { nil }
    func emojiPresentation(for node: RichContentNode, content: RichEmojiContent) -> RichInlineImagePresentation? { nil }
    func imagePresentation(for node: RichContentNode, content: RichImageContent) -> RichInlineImagePresentation? { nil }
    func linkIconPresentation(for node: RichContentNode, content: RichLinkContent) -> RichInlineImagePresentation? { nil }
    func resolvedLink(for node: RichContentNode, content: RichLinkContent) -> RichContentResolvedLink? { nil }
}

public struct RichContentRenderingConfiguration {
    public let font: UIFont
    public let lineHeight: CGFloat
    public let textColor: UIColor
    public let secondaryTextColor: UIColor
    public let linkColor: UIColor
    public let currentMentionTextColor: UIColor
    public let currentMentionBackgroundColor: UIColor
    public let mentionSpacing: CGFloat
    public let contrastBackgroundColor: UIColor
    public let blockQuoteColor: UIColor
    public let codeBackgroundColor: UIColor
    public let dividerColor: UIColor
    public let dividerHeight: CGFloat
    public let dividerExtent: CGFloat
    public let highlightTextColor: UIColor
    public let highlightBackgroundColor: UIColor
    public let highlightedMentionIDs: Set<String>
    public let highlightTokens: [String]
    public let resolvedLinks: [String: RichContentResolvedLink]
    public let excludedNodeIDs: Set<String>
    public let leadingElements: [RichElement]
    public let metrics: RichContentLayoutMetrics
    public let commandTextColor: UIColor
    public let textForegroundColorResolver: ((UIColor?, UIColor?, UIColor, UIColor) -> UIColor)?

    public static var standard: Self {
        let font = UIFont.preferredFont(forTextStyle: .body)
        return Self(
            font: font,
            lineHeight: font.lineHeight,
            textColor: .label,
            secondaryTextColor: .secondaryLabel,
            linkColor: .link,
            currentMentionTextColor: .label,
            currentMentionBackgroundColor: .tertiarySystemFill,
            contrastBackgroundColor: .secondarySystemBackground,
            blockQuoteColor: .separator,
            codeBackgroundColor: .secondarySystemBackground,
            highlightTextColor: .label,
            highlightBackgroundColor: .systemYellow
        )
    }

    public init(
        font: UIFont,
        lineHeight: CGFloat,
        textColor: UIColor,
        secondaryTextColor: UIColor,
        linkColor: UIColor,
        currentMentionTextColor: UIColor,
        currentMentionBackgroundColor: UIColor,
        mentionSpacing: CGFloat = 4,
        contrastBackgroundColor: UIColor,
        blockQuoteColor: UIColor,
        codeBackgroundColor: UIColor,
        highlightTextColor: UIColor,
        highlightBackgroundColor: UIColor,
        highlightedMentionIDs: Set<String> = [],
        highlightTokens: [String] = [],
        resolvedLinks: [String: RichContentResolvedLink] = [:],
        excludedNodeIDs: Set<String> = [],
        leadingElements: [RichElement] = [],
        metrics: RichContentLayoutMetrics = RichContentLayoutMetrics(),
        commandTextColor: UIColor? = nil,
        dividerColor: UIColor? = nil,
        dividerHeight: CGFloat = 1,
        dividerExtent: CGFloat = 9,
        textForegroundColorResolver: ((UIColor?, UIColor?, UIColor, UIColor) -> UIColor)? = nil
    ) {
        self.font = font
        self.lineHeight = lineHeight
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.currentMentionTextColor = currentMentionTextColor
        self.currentMentionBackgroundColor = currentMentionBackgroundColor
        self.mentionSpacing = max(0, mentionSpacing)
        self.contrastBackgroundColor = contrastBackgroundColor
        self.blockQuoteColor = blockQuoteColor
        self.codeBackgroundColor = codeBackgroundColor
        self.dividerColor = dividerColor ?? blockQuoteColor
        self.dividerHeight = dividerHeight
        self.dividerExtent = dividerExtent
        self.highlightTextColor = highlightTextColor
        self.highlightBackgroundColor = highlightBackgroundColor
        self.highlightedMentionIDs = highlightedMentionIDs
        self.highlightTokens = highlightTokens
        self.resolvedLinks = resolvedLinks
        self.excludedNodeIDs = excludedNodeIDs
        self.leadingElements = leadingElements
        self.metrics = metrics
        self.commandTextColor = commandTextColor ?? textColor
        self.textForegroundColorResolver = textForegroundColorResolver
    }
}

public struct RichContentRenderContext {
    public let constrainedWidth: CGFloat
    public let configuration: RichContentRenderingConfiguration
    public let resolver: (any RichContentPresentationResolving)?
    let needsLeadingInlineSpacing: Bool
    let needsTrailingInlineSpacing: Bool

    public init(
        constrainedWidth: CGFloat,
        configuration: RichContentRenderingConfiguration,
        resolver: (any RichContentPresentationResolving)? = nil
    ) {
        self.constrainedWidth = constrainedWidth
        self.configuration = configuration
        self.resolver = resolver
        needsLeadingInlineSpacing = false
        needsTrailingInlineSpacing = false
    }

    init(
        constrainedWidth: CGFloat,
        configuration: RichContentRenderingConfiguration,
        resolver: (any RichContentPresentationResolving)?,
        needsLeadingInlineSpacing: Bool,
        needsTrailingInlineSpacing: Bool
    ) {
        self.constrainedWidth = constrainedWidth
        self.configuration = configuration
        self.resolver = resolver
        self.needsLeadingInlineSpacing = needsLeadingInlineSpacing
        self.needsTrailingInlineSpacing = needsTrailingInlineSpacing
    }
}
