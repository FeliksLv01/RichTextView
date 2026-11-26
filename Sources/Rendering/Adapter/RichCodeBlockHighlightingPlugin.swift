import Foundation

public protocol RichCodeBlockHighlightingPlugin: AnyObject, Sendable {
    func releaseIncrementalState(for nodeID: String)

    func codeBlockPresentation(
        for code: String,
        language: String,
        nodeID: String
    ) -> RichCodeBlockPresentation?
}

public extension RichCodeBlockHighlightingPlugin {
    func releaseIncrementalState(for nodeID: String) {}
}

public enum RichCodeBlockHighlighting {
    private static let themedHighlighter = RichSyntaxHighlighter(maximumCachedCodeBlocks: 64)

    public static func releaseIncrementalState(for nodeID: String) {
        storage.plugin?.releaseIncrementalState(for: nodeID)
    }

    public static func useBuiltIn(
        theme: RichCodeHighlightTheme = .default,
        maximumCachedCodeBlocks: Int = 64
    ) {
        register(RichBuiltInCodeBlockHighlightingPlugin(
            theme: theme,
            highlighter: RichSyntaxHighlighter(maximumCachedCodeBlocks: maximumCachedCodeBlocks)
        ))
    }

    public static func register(_ plugin: any RichCodeBlockHighlightingPlugin) {
        storage.setPlugin(plugin)
    }

    public static func unregister() {
        storage.setPlugin(nil)
    }

    public static func presentation(
        for code: String,
        language: String,
        nodeID: String
    ) -> RichCodeBlockPresentation? {
        presentation(for: code, language: language, nodeID: nodeID, streaming: false)
    }

    static func presentation(for code: String, language: String, nodeID: String, streaming: Bool) -> RichCodeBlockPresentation? {
        guard let plugin = storage.plugin else { return nil }
        defer { if !streaming { plugin.releaseIncrementalState(for: nodeID) } }
        return plugin.codeBlockPresentation(
            for: code,
            language: language,
            nodeID: nodeID
        )
    }

    public static func presentation(
        for code: String,
        language: String,
        nodeID: String,
        theme: RichCodeHighlightTheme
    ) -> RichCodeBlockPresentation? {
        defer { themedHighlighter.releaseIncrementalState(for: nodeID) }
        return RichBuiltInCodeBlockHighlightingPlugin(
            theme: theme,
            highlighter: themedHighlighter
        ).codeBlockPresentation(for: code, language: language, nodeID: nodeID)
    }

    private static let storage = RichCodeBlockHighlightingStorage()
}

private final class RichCodeBlockHighlightingStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPlugin: (any RichCodeBlockHighlightingPlugin)?

    var plugin: (any RichCodeBlockHighlightingPlugin)? {
        lock.lock()
        defer { lock.unlock() }
        return storedPlugin
    }

    func setPlugin(_ plugin: (any RichCodeBlockHighlightingPlugin)?) {
        lock.lock()
        storedPlugin = plugin
        lock.unlock()
    }
}
