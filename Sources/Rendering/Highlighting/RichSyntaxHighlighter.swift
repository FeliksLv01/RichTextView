import Foundation
internal import SwiftTreeSitter
internal import TreeSitterSwift
import UIKit

final class RichSyntaxHighlighter: @unchecked Sendable {
    private final class State {
        let parser: Parser
        let query: Query
        var previousSource = ""
        var previousTree: MutableTree?
        var lastAccess: UInt64 = 0

        init() throws {
            let language = Language(language: tree_sitter_swift())
            let parser = Parser()
            try parser.setLanguage(language)
            self.parser = parser
            query = try Query(language: language, data: RichSwiftHighlightQuery.data)
        }
    }

    private let queue = DispatchQueue(label: "io.github.felikslv01.rich-text-view.syntax-highlighter")
    private let maximumCachedCodeBlocks: Int
    private var states: [String: State] = [:]
    private var accessCounter: UInt64 = 0

    init(maximumCachedCodeBlocks: Int) {
        self.maximumCachedCodeBlocks = max(1, maximumCachedCodeBlocks)
    }

    func highlight(code: String, language: String, nodeID: String, theme: RichCodeHighlightTheme) -> NSAttributedString? {
        guard Self.isSwift(language) else { return nil }
        return queue.sync {
            guard let state = state(for: nodeID), let tree = updatedTree(for: code, state: state),
                  let root = tree.rootNode else { return nil }
            let value = baseAttributedString(code: code, theme: theme)
            let highlights = state.query.execute(node: root, in: tree)
                .resolve(with: Predicate.Context(string: code))
                .highlights()
            for highlight in highlights where NSMaxRange(highlight.range) <= value.length {
                guard let style = theme.style(for: highlight.name) else { continue }
                if let color = style.foregroundColor { value.addAttribute(.foregroundColor, value: color, range: highlight.range) }
                if let color = style.backgroundColor { value.addAttribute(.backgroundColor, value: color, range: highlight.range) }
                if let font = style.font { value.addAttribute(.font, value: font, range: highlight.range) }
            }
            return value
        }
    }

    private func state(for nodeID: String) -> State? {
        accessCounter &+= 1
        if let state = states[nodeID] {
            state.lastAccess = accessCounter
            return state
        }
        guard let state = try? State() else { return nil }
        state.lastAccess = accessCounter
        states[nodeID] = state
        if states.count > maximumCachedCodeBlocks,
           let key = states.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            states.removeValue(forKey: key)
        }
        return state
    }

    private func updatedTree(for source: String, state: State) -> MutableTree? {
        defer { state.previousSource = source }
        guard source.hasPrefix(state.previousSource), let previousTree = state.previousTree else {
            let tree = state.parser.parse(source)
            state.previousTree = tree
            return tree
        }
        let oldPoint = endPoint(of: state.previousSource)
        previousTree.edit(InputEdit(
            startByte: state.previousSource.utf16.count * 2,
            oldEndByte: state.previousSource.utf16.count * 2,
            newEndByte: source.utf16.count * 2,
            startPoint: oldPoint,
            oldEndPoint: oldPoint,
            newEndPoint: endPoint(of: source)
        ))
        let tree = state.parser.parse(tree: previousTree, string: source)
        state.previousTree = tree
        return tree
    }

    private func baseAttributedString(code: String, theme: RichCodeHighlightTheme) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = theme.lineHeight
        paragraph.maximumLineHeight = theme.lineHeight
        paragraph.lineBreakMode = .byClipping
        return NSMutableAttributedString(string: code, attributes: [
            .font: theme.font,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraph
        ])
    }

    private func endPoint(of source: String) -> Point {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        return Point(row: max(0, lines.count - 1), column: (lines.last?.utf16.count ?? 0) * 2)
    }

    private static func isSwift(_ identifier: String) -> Bool {
        ["swift", "swiftlang"].contains(identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

final class RichBuiltInCodeBlockHighlightingPlugin: RichCodeBlockHighlightingPlugin, @unchecked Sendable {
    private let theme: RichCodeHighlightTheme
    private let highlighter: RichSyntaxHighlighter

    init(theme: RichCodeHighlightTheme, maximumCachedCodeBlocks: Int) {
        self.theme = theme
        highlighter = RichSyntaxHighlighter(maximumCachedCodeBlocks: maximumCachedCodeBlocks)
    }

    func codeBlockPresentation(for code: String, language: String, nodeID: String) -> RichCodeBlockPresentation? {
        guard let attributedCode = highlighter.highlight(code: code, language: language, nodeID: nodeID, theme: theme) else {
            return nil
        }
        return RichCodeBlockPresentation(
            attributedCode: attributedCode,
            backgroundColor: theme.backgroundColor,
            contentInsets: RichContainerInsets(
                top: theme.codeBlockInsets.top,
                left: theme.codeBlockInsets.left,
                bottom: theme.codeBlockInsets.bottom,
                right: theme.codeBlockInsets.right
            ),
            cornerRadius: theme.codeBlockCornerRadius
        )
    }
}
