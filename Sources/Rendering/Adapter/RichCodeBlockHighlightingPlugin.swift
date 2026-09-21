import Foundation

public protocol RichCodeBlockHighlightingPlugin: AnyObject, Sendable {
    func codeBlockPresentation(
        for code: String,
        language: String,
        nodeID: String
    ) -> RichCodeBlockPresentation?
}

public enum RichCodeBlockHighlighting {
    public static func useBuiltIn(
        theme: RichCodeHighlightTheme = .default,
        maximumCachedCodeBlocks: Int = 64
    ) {
        register(RichBuiltInCodeBlockHighlightingPlugin(
            theme: theme,
            maximumCachedCodeBlocks: maximumCachedCodeBlocks
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
        storage.plugin?.codeBlockPresentation(
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
        RichBuiltInCodeBlockHighlightingPlugin(
            theme: theme,
            maximumCachedCodeBlocks: 1
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
