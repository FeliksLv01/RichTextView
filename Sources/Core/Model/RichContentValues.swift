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

public struct RichTextContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let text: String
    public let style: RichTextStyle

    public init(text: String, style: RichTextStyle = RichTextStyle()) {
        self.text = text
        self.style = style
    }

    public var richContentLayoutSignature: String {
        "\(text)|\(style.bold)|\(style.italic)|\(style.code)|\(style.fontScale)"
    }

    public var richContentDisplaySignature: String {
        "\(richContentLayoutSignature)|\(style.underline)|\(style.strikethrough)|\(style.foregroundColor ?? "")|\(style.backgroundColor ?? "")"
    }
}

public struct RichMentionContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let id: String
    public let name: String
    public let mentionType: String

    public init(id: String, name: String, mentionType: String) {
        self.id = id
        self.name = name
        self.mentionType = mentionType
    }

    public var richContentLayoutSignature: String { "\(id)|\(name)|\(mentionType)" }
}

public struct RichEmojiContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    public var richContentLayoutSignature: String { "\(code)|\(name)" }
}

public struct RichLinkContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
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

    public var richContentLayoutSignature: String {
        "\(href)|\(title)|\(icon)|\(linkType)|\(editStatus)|\(viewType)"
    }
}

public struct RichCommandContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
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

    public var richContentLayoutSignature: String { "\(id)|\(kind)|\(label)|\(icon)|\(content)" }
}

public struct RichListContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let level: Int
    public let index: Int?

    public init(level: Int, index: Int? = nil) {
        self.level = max(1, level)
        self.index = index
    }

    public var richContentLayoutSignature: String { "\(level)|\(index.map(String.init) ?? "")" }
}

public struct RichAttachmentContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let sourceIdentifier: String
    public let width: Int
    public let height: Int

    public init(sourceIdentifier: String = "", width: Int = 0, height: Int = 0) {
        self.sourceIdentifier = sourceIdentifier
        self.width = width
        self.height = height
    }

    public var richContentLayoutSignature: String { "\(width)|\(height)" }
    public var richContentDisplaySignature: String { "\(sourceIdentifier)|\(richContentLayoutSignature)" }
}

public struct RichUnknownContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let sourceType: String

    public init(sourceType: String) {
        self.sourceType = sourceType
    }

    public var richContentLayoutSignature: String { sourceType }
}

public struct RichImageContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let source: String
    public let title: String
    public let size: CGSize

    public init(source: String, title: String = "", size: CGSize) {
        precondition(size.width > 0 && size.height > 0, "Image node size must be positive")
        self.source = source
        self.title = title
        self.size = size
    }

    public var richContentLayoutSignature: String { "\(title)|\(size.width)|\(size.height)" }
    public var richContentDisplaySignature: String { "\(source)|\(title)" }
}

public struct RichCodeBlockContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let language: String

    public init(language: String = "") {
        self.language = language
    }

    public var richContentLayoutSignature: String { language }
}

public enum RichTableCellAlignment: String, Hashable, Sendable {
    case natural
    case left
    case center
    case right
}

public struct RichTableCellContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let alignment: RichTableCellAlignment

    public init(alignment: RichTableCellAlignment = .natural) {
        self.alignment = alignment
    }

    public var richContentLayoutSignature: String { alignment.rawValue }
}

public struct RichHeadingContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let level: Int

    public init(level: Int) {
        self.level = min(max(level, 1), 6)
    }

    public var richContentLayoutSignature: String { String(level) }
}

public struct RichMarkdownLiteralContent: RichContentNodeContent, RichContentNodeContentSignatureProviding {
    public let literal: String

    public init(literal: String) {
        self.literal = literal
    }

    public var richContentLayoutSignature: String { literal }
}
