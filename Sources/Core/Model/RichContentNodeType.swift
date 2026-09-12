import Foundation

public struct RichContentNodeType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "Rich content node type must not be empty")
        self.rawValue = rawValue
    }
}

public extension RichContentNodeType {
    static let root = Self(rawValue: "root")
    static let paragraph = Self(rawValue: "paragraph")
    static let inline = Self(rawValue: "inline")
    static let heading = Self(rawValue: "heading")
    static let columns = Self(rawValue: "columns")
    static let column = Self(rawValue: "column")
    static let numberedList = Self(rawValue: "numbered-list")
    static let bulletedList = Self(rawValue: "bulleted-list")
    static let blockQuote = Self(rawValue: "block-quote")
    static let codeBlock = Self(rawValue: "code-block")
    static let table = Self(rawValue: "table")
    static let tableHead = Self(rawValue: "table-head")
    static let tableBody = Self(rawValue: "table-body")
    static let tableRow = Self(rawValue: "table-row")
    static let tableCell = Self(rawValue: "table-cell")
    static let divider = Self(rawValue: "divider")
    static let markdownHTML = Self(rawValue: "markdown-html")
    static let reference = Self(rawValue: "reference")
    static let text = Self(rawValue: "text")
    static let mention = Self(rawValue: "mention")
    static let emoji = Self(rawValue: "emoji")
    static let link = Self(rawValue: "link")
    static let command = Self(rawValue: "command")
    static let image = Self(rawValue: "image")
    static let video = Self(rawValue: "video")
    static let file = Self(rawValue: "file")
    static let sticker = Self(rawValue: "sticker")
    static let forward = Self(rawValue: "forward")
}
