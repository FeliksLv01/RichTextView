import XCTest
import UIKit
@testable import RichTextView
#if SWIFT_PACKAGE
@testable import RichTextViewMarkdown
#endif

final class RichMarkdownParserTests: XCTestCase {
    func testStrikethroughRequiresDoubleTilde() {
        let result = RichMarkdownParser().parse("~single~ and ~~double~~", documentID: "document")
        let textNodes = flatten(result.document.root).compactMap { $0.content(as: RichTextContent.self) }

        XCTAssertTrue(textNodes.contains { $0.text.contains("~single~") && !$0.style.strikethrough })
        XCTAssertTrue(textNodes.contains { $0.text == "double" && $0.style.strikethrough })
    }

    @MainActor
    func testMarkdownTableUsesBuiltInScrollableAttachment() throws {
        let parsed = RichMarkdownParser().parse(
            """
            | Name | Description | Status |
            | :--- | :---------- | -----: |
            | RichTextView | A deliberately long description that makes the table wider than its viewport. | Ready |
            """,
            documentID: "table"
        )
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 240,
            configuration: .standard
        )
        let attachment = try XCTUnwrap(flattenElements(rendered.snapshot.root).compactMap {
            $0 as? RichAttachmentElement
        }.first { $0.reuseIdentifier == RichTableViewProvider.reuseIdentifier })
        let provider = try XCTUnwrap(attachment.provider as? RichTableViewProvider)
        let tableView = provider.makeView()
        tableView.frame = CGRect(origin: .zero, size: attachment.metrics.size)
        provider.updateView(tableView)
        tableView.layoutIfNeeded()
        let scrollView = try XCTUnwrap(tableView.subviews.compactMap { $0 as? UIScrollView }.first)

        XCTAssertTrue(rendered.unhandledNodeTypes.isEmpty)
        XCTAssertEqual(attachment.metrics.size.width, 240)
        XCTAssertGreaterThan(attachment.metrics.size.height, 70)
        XCTAssertTrue(scrollView.isScrollEnabled)
        XCTAssertGreaterThan(scrollView.contentSize.width, scrollView.bounds.width)
        XCTAssertEqual(
            attachment.copyText,
            "Name\tDescription\tStatus\nRichTextView\tA deliberately long description that makes the table wider than its viewport.\tReady"
        )
    }

    func testMarkdownTablePreservesAlignmentAndStableIdentityAcrossStreamingAppend() throws {
        let parser = RichMarkdownParser()
        let initial = parser.parse(
            "| Left | Right |\n| :--- | ---: |\n| A | 1 |",
            documentID: "stream-table"
        )
        let updated = parser.parse(
            "| Left | Right |\n| :--- | ---: |\n| A | 1 |\n| B | 2 |",
            documentID: "stream-table",
            previousDocument: initial.document
        )
        let initialTable = try XCTUnwrap(flatten(initial.document.root).first { $0.type == .table })
        let updatedTable = try XCTUnwrap(flatten(updated.document.root).first { $0.type == .table })
        let cells = flatten(updatedTable).filter { $0.type == .tableCell }

        XCTAssertEqual(initialTable.id, updatedTable.id)
        XCTAssertGreaterThan(updatedTable.revision.layout, initialTable.revision.layout)
        XCTAssertEqual(cells.first?.content(as: RichTableCellContent.self)?.alignment, .left)
        XCTAssertEqual(cells.dropFirst().first?.content(as: RichTableCellContent.self)?.alignment, .right)
    }

    @MainActor
    func testInlineCodeAndFencedCodeUseDistinctPresentations() throws {
        let parsed = RichMarkdownParser().parse(
            "Use `inlineCode` here.\n\n```swift\nlet value = 42\n```",
            documentID: "code"
        )
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 320,
            configuration: .standard,
            resolver: TestCodeResolver()
        )
        let elements = flattenElements(rendered.snapshot.root)
        let inlineCode = try XCTUnwrap(elements.compactMap { $0 as? RichTextBadgeElement }.first {
            $0.attributedText.string == "inlineCode"
        })
        let highlightedCode = try XCTUnwrap(elements.compactMap { $0 as? RichAttachmentElement }.first {
            $0.reuseIdentifier == RichCodeBlockViewProvider.reuseIdentifier
        })
        let provider = try XCTUnwrap(highlightedCode.provider as? RichCodeBlockViewProvider)

        XCTAssertNotNil(inlineCode.attributedText.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(inlineCode.cornerRadius, 4)
        XCTAssertEqual(inlineCode.borderWidth, 1)
        XCTAssertEqual(highlightedCode.copyText, "let value = 42")
        XCTAssertTrue(highlightedCode.isSelectable)
        XCTAssertGreaterThan(provider.requiredHeight, 24)
        let longLine = NSAttributedString(
            string: "view.isTextSelectionEnabled = true",
            attributes: [.font: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)]
        )
        XCTAssertGreaterThan(
            RichCodeBlockViewProvider.requiredContentSize(
                for: longLine,
                contentInsets: RichContainerInsets(top: 12, left: 16, bottom: 12, right: 16)
            ).width,
            320
        )
        XCTAssertTrue(rendered.unhandledNodeTypes.isEmpty)
    }

    @MainActor
    func testMarkdownEntryPointRendersThroughUnifiedNodeTree() {
        let parsed = RichMarkdownParser().parse(
            "# Title\n\nText before ![Image](example://image) and after.",
            documentID: "markdown"
        )
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 320,
            configuration: .standard,
            resolver: TestImageResolver()
        )
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 1_000))
        view.laysOutAsynchronously = false
        view.isTextSelectionEnabled = true

        view.apply(rendered.snapshot)

        XCTAssertTrue(rendered.unhandledNodeTypes.isEmpty)
        XCTAssertEqual(view.currentSnapshot?.root.id, "markdown")
        XCTAssertGreaterThan(view.currentLayout?.contentSize.height ?? 0, 0)
        XCTAssertTrue(containsImage(rendered.snapshot.root))
        XCTAssertTrue(view.isTextSelectionEnabled)
    }

    @MainActor
    func testRegisteredCodeBlockHighlightingPluginIsUsed() {
        let plugin = TestCodePlugin(color: .systemGreen)
        RichCodeBlockHighlighting.register(plugin)
        defer { RichCodeBlockHighlighting.unregister() }

        renderCodeBlock(resolver: nil)

        XCTAssertEqual(plugin.callCount, 1)
    }

    func testBuiltInCodeBlockHighlightingParsesSwiftAndFallsBackForUnknownLanguage() throws {
        RichCodeBlockHighlighting.useBuiltIn(theme: .github)
        defer { RichCodeBlockHighlighting.unregister() }

        let presentation = try XCTUnwrap(RichCodeBlockHighlighting.presentation(
            for: "let value = 42",
            language: "swift",
            nodeID: "built-in-code"
        ))

        XCTAssertEqual(presentation.attributedCode.string, "let value = 42")
        XCTAssertNotNil(presentation.attributedCode.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        XCTAssertNil(RichCodeBlockHighlighting.presentation(
            for: "value",
            language: "unsupported-language",
            nodeID: "plain-code"
        ))
    }

    @MainActor
    func testExplicitResolverPrecedesRegisteredCodeBlockHighlightingPlugin() {
        let plugin = TestCodePlugin(color: .systemGreen)
        RichCodeBlockHighlighting.register(plugin)
        defer { RichCodeBlockHighlighting.unregister() }

        renderCodeBlock(resolver: TestCodeResolver())

        XCTAssertEqual(plugin.callCount, 0)
    }

    private func renderCodeBlock(
        resolver: (any RichContentPresentationResolving)?
    ) {
        let parsed = RichMarkdownParser().parse(
            "```swift\nlet value = 42\n```",
            documentID: "plugin-code"
        )
        _ = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 320,
            configuration: .standard,
            resolver: resolver
        )
    }

    private func containsImage(_ element: RichElement) -> Bool {
        if element is RichImageElement { return true }
        return (element as? RichContainerElement)?.children.contains(where: containsImage) == true
    }

    private func flattenElements(_ element: RichElement) -> [RichElement] {
        [element] + element.children.flatMap(flattenElements)
    }

    private final class TestImageResolver: RichContentPresentationResolving {
        func imagePresentation(
            for node: RichContentNode,
            content: RichImageContent
        ) -> RichInlineImagePresentation? {
            RichInlineImagePresentation(
                source: RichImageSource(identifier: content.source, image: UIImage(systemName: "photo")),
                size: CGSize(width: 24, height: 20),
                copyText: content.title,
                accessibilityLabel: content.title
            )
        }
    }

    private final class TestCodeResolver: RichContentPresentationResolving {
        func codeBlockPresentation(
            for node: RichContentNode,
            content: RichCodeBlockContent,
            code: String,
            context: RichContentRenderContext
        ) -> RichCodeBlockPresentation? {
            RichCodeBlockPresentation(
                attributedCode: NSAttributedString(
                    string: code,
                    attributes: [.foregroundColor: UIColor.systemPink]
                )
            )
        }
    }

    private final class TestCodePlugin: RichCodeBlockHighlightingPlugin, @unchecked Sendable {
        private let color: UIColor
        private let lock = NSLock()
        private var storedCallCount = 0

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedCallCount
        }

        init(color: UIColor) {
            self.color = color
        }

        func codeBlockPresentation(
            for code: String,
            language: String,
            nodeID: String
        ) -> RichCodeBlockPresentation? {
            lock.lock()
            storedCallCount += 1
            lock.unlock()
            return RichCodeBlockPresentation(
                attributedCode: NSAttributedString(
                    string: code,
                    attributes: [.foregroundColor: color]
                )
            )
        }
    }

    private func flatten(_ node: RichContentNode) -> [RichContentNode] {
        [node] + node.children.flatMap(flatten)
    }
}
