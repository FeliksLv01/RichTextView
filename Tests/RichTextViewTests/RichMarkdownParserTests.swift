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
