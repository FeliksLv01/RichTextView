import CoreGraphics
import Foundation

public struct RichTextStyle: Hashable, Sendable {
    public let bold: Bool
    public let italic: Bool
    public let underline: Bool
    public let strikethrough: Bool
    public let code: Bool
    public let fontScale: Double
    public let foregroundColor: String?
    public let backgroundColor: String?

    public init(
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        code: Bool = false,
        fontScale: Double = 1,
        foregroundColor: String? = nil,
        backgroundColor: String? = nil
    ) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.code = code
        self.fontScale = fontScale
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }
}

public struct RichTextContent: RichContentNodeContent, Equatable {
    public let text: String
    public let style: RichTextStyle

    public init(text: String, style: RichTextStyle = RichTextStyle()) {
        self.text = text
        self.style = style
    }
}

public struct RichMentionContent: RichContentNodeContent, Equatable {
    public let id: String
    public let name: String
    public let mentionType: String

    public init(id: String, name: String, mentionType: String) {
        self.id = id
        self.name = name
        self.mentionType = mentionType
    }
}

public struct RichEmojiContent: RichContentNodeContent, Equatable {
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public struct RichLinkContent: RichContentNodeContent, Equatable {
    public let href: String
    public let title: String
    public let icon: String
    public let linkType: Int
    public let editStatus: Int
    public let viewType: String

    public init(
        href: String,
        title: String,
        icon: String,
        linkType: Int = 0,
        editStatus: Int = 0,
        viewType: String = ""
    ) {
        self.href = href
        self.title = title
        self.icon = icon
        self.linkType = linkType
        self.editStatus = editStatus
        self.viewType = viewType
    }
}

public struct RichCommandContent: RichContentNodeContent, Equatable {
    public let id: String
    public let kind: Int
    public let label: String
    public let icon: String
    public let content: String

    public init(id: String, kind: Int, label: String, icon: String, content: String) {
        self.id = id
        self.kind = kind
        self.label = label
        self.icon = icon
        self.content = content
    }
}

public struct RichListContent: RichContentNodeContent, Equatable {
    public let level: Int
    public let index: Int?

    public init(level: Int, index: Int? = nil) {
        self.level = max(1, level)
        self.index = index
    }
}

public struct RichAttachmentContent: RichContentNodeContent, Equatable {
    public let sourceIdentifier: String
    public let width: Int
    public let height: Int

    public init(sourceIdentifier: String = "", width: Int = 0, height: Int = 0) {
        self.sourceIdentifier = sourceIdentifier
        self.width = width
        self.height = height
    }
}

public struct RichUnknownContent: RichContentNodeContent, Equatable {
    public let sourceType: String

    public init(sourceType: String) {
        self.sourceType = sourceType
    }
}

public struct RichImageContent: RichContentNodeContent, Equatable {
    public let source: String
    public let title: String
    public let size: CGSize

    public init(source: String, title: String = "", size: CGSize) {
        precondition(size.width > 0 && size.height > 0, "Image node size must be positive")
        self.source = source
        self.title = title
        self.size = size
    }
}

public struct RichCodeBlockContent: RichContentNodeContent, Equatable {
    public let language: String

    public init(language: String = "") {
        self.language = language
    }
}

public struct RichMathContent: RichContentNodeContent, Equatable {
    public let latex: String
    public let isBlock: Bool

    public init(latex: String, isBlock: Bool) {
        self.latex = latex
        self.isBlock = isBlock
    }
}

public enum RichTableCellAlignment: String, Hashable, Sendable {
    case natural
    case left
    case center
    case right
}

public struct RichTableCellContent: RichContentNodeContent, Equatable {
    public let alignment: RichTableCellAlignment

    public init(alignment: RichTableCellAlignment = .natural) {
        self.alignment = alignment
    }
}

public struct RichHeadingContent: RichContentNodeContent, Equatable {
    public let level: Int

    public init(level: Int) {
        self.level = min(max(level, 1), 6)
    }
}

public struct RichMarkdownLiteralContent: RichContentNodeContent, Equatable {
    public let literal: String

    public init(literal: String) {
        self.literal = literal
    }
}
