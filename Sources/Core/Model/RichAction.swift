import Foundation

public struct RichAction: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case link(URL)
        case mention(id: String)
        case copyCode(nodeID: String)
        case codeBlock(nodeID: String)
        case custom(String, payload: [String: String] = [:])
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var legacyIdentifier: String {
        switch kind {
        case let .link(url): "link:\(url.absoluteString)"
        case let .mention(id): "mention:\(id)"
        case let .copyCode(id): "copy-code:\(id)"
        case let .codeBlock(id): "code-block:\(id)"
        case let .custom(name, _): name
        }
    }

    public init?(legacyIdentifier: String) {
        guard !legacyIdentifier.isEmpty else { return nil }
        guard let colon = legacyIdentifier.firstIndex(of: ":") else {
            self.init(.custom(legacyIdentifier))
            return
        }
        let value = String(legacyIdentifier[legacyIdentifier.index(after: colon)...])
        switch legacyIdentifier[..<colon] {
        case "link":
            self.init(URL(string: value).map(Kind.link) ?? .custom(legacyIdentifier))
        case "mention": self.init(.mention(id: value))
        case "copy-code": self.init(.copyCode(nodeID: value))
        case "code-block": self.init(.codeBlock(nodeID: value))
        default: self.init(.custom(legacyIdentifier))
        }
    }
}

public extension NSAttributedString.Key {
    static let richAction = NSAttributedString.Key("io.github.felikslv01.rich-text-view.action")
}
