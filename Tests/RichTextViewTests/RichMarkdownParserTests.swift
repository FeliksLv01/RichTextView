import XCTest
import UIKit
import iosMath
@testable import RichTextView
#if SWIFT_PACKAGE
@testable import RichTextViewMarkdown
#endif

final class RichMarkdownParserTests: XCTestCase {
    func testStreamingSpeculativelyClosesEmphasisAndMath() {
        let parser = makeParser()
        let strong = parser.parse("Prefix ** ddddd", documentID: "strong", streaming: true)
        let strongText = flatten(strong.document.root).compactMap { $0.content(as: RichTextContent.self) }
        let math = parser.parse("Value \\(x^2", documentID: "math", streaming: true)

        XCTAssertEqual(strong.plainText, "Prefix  ddddd")
        XCTAssertTrue(strongText.contains { $0.text == " ddddd" && $0.style.bold })
        XCTAssertTrue(flatten(math.document.root).contains { $0.type == .math })
    }

    func testCompleteParsingKeepsUnclosedMarkupLiteral() {
        let parsed = makeParser().parse("Prefix ** ddddd and \\(x^2", documentID: "literal")

        XCTAssertEqual(parsed.plainText, "Prefix ** ddddd and (x^2")
        XCTAssertFalse(flatten(parsed.document.root).contains { $0.type == .math })
    }

    @MainActor
    func testThirdLevelBulletIsSmallerThanParentBullets() throws {
        let parsed = makeParser().parse(
            "- 111\n  - 222\n    - eeee",
            documentID: "nested-bullets"
        )
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 320,
            configuration: .standard
        )
        let markers = flattenElements(rendered.snapshot.root).compactMap { element -> NSAttributedString? in
            guard
                let container = element as? RichContainerElement,
                case let .listMarker(attributedText, _) = container.decoration
            else { return nil }
            return attributedText
        }
        let fonts = try markers.map { marker in
            try XCTUnwrap(marker.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        }

        XCTAssertEqual(markers.map(\.string), ["•", "◦", "▪"])
        XCTAssertEqual(fonts[0].pointSize, fonts[1].pointSize)
        XCTAssertEqual(fonts[2].pointSize, fonts[1].pointSize * 0.4, accuracy: 0.001)
        XCTAssertEqual(
            markers[2].attribute(.baselineOffset, at: 0, effectiveRange: nil) as? CGFloat,
            (fonts[1].xHeight - fonts[2].capHeight) / 2
        )
    }

    @MainActor
    func testInlineAndBlockMathRenderAsNativeLabels() throws {
        let parsed = makeParser().parse(
            "Inline \\(x^2 + y^2\\).\n\n$$\n\\frac{a}{b}\n$$",
            documentID: "math"
        )
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 320,
            configuration: .standard
        )
        let attachments = flattenElements(rendered.snapshot.root).compactMap { $0 as? RichAttachmentElement }
        let inline = try XCTUnwrap(attachments.first { if case .inline = $0.display { true } else { false } })
        let block = try XCTUnwrap(attachments.first { if case .block = $0.display { true } else { false } })

        XCTAssertEqual(attachments.count, 2)
        let inlineLabel = try XCTUnwrap(inline.provider.makeView() as? MTMathUILabel)
        let blockLabel = try XCTUnwrap(block.provider.makeView() as? MTMathUILabel)
        XCTAssertEqual(inlineLabel.textAlignment, .left)
        XCTAssertEqual(blockLabel.textAlignment, .center)
        XCTAssertEqual(block.metrics.size.width, 320)
        XCTAssertEqual(inline.accessibilityLabel, "x^2 + y^2")
        XCTAssertEqual(block.accessibilityLabel, "\\frac{a}{b}")
        XCTAssertGreaterThan(inline.metrics.size.width, 0)
        XCTAssertGreaterThan(block.metrics.size.height, 0)
        XCTAssertTrue(rendered.unhandledNodeTypes.isEmpty)
    }

    func testStrikethroughRequiresDoubleTilde() {
        let result = makeParser().parse("~single~ and ~~double~~", documentID: "document")
        let textNodes = flatten(result.document.root).compactMap { $0.content(as: RichTextContent.self) }

        XCTAssertTrue(textNodes.contains { $0.text.contains("~single~") && !$0.style.strikethrough })
        XCTAssertTrue(textNodes.contains { $0.text == "double" && $0.style.strikethrough })
    }

    @MainActor
    func testMarkdownTableUsesBuiltInScrollableAttachment() throws {
        let parsed = makeParser().parse(
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
        let parser = makeParser()
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

    func testTableAfterBlockQuoteRemainsASeparateNode() {
        let parsed = makeParser().parse(
            """
            > A streamed quote.

            | Layer | Result |
            | :--- | ---: |
            | Parser | Stable IDs |
            """,
            documentID: "quote-followed-by-table"
        )
        let nodes = flatten(parsed.document.root)

        XCTAssertEqual(nodes.filter { $0.type == .blockQuote }.count, 1)
        XCTAssertEqual(nodes.filter { $0.type == .table }.count, 1)
    }

    @MainActor
    func testRightAlignedTableCellUsesTextWidthInsteadOfAlignmentOffset() throws {
        let parsed = makeParser().parse(
            "| Layer | Result |\n| :--- | ---: |\n| Parser | Stable IDs |",
            documentID: "right-aligned-table"
        )
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 320,
            configuration: .standard
        )
        let attachment = try XCTUnwrap(flattenElements(rendered.snapshot.root).compactMap {
            $0 as? RichAttachmentElement
        }.first { $0.reuseIdentifier == RichTableViewProvider.reuseIdentifier })
        let provider = try XCTUnwrap(attachment.provider as? RichTableViewProvider)
        let model = provider.model
        let lastEdge = try XCTUnwrap(model.columnEdges.last)
        let rightColumnWidth = lastEdge - model.columnEdges[1]

        XCTAssertLessThan(rightColumnWidth, model.style.maximumColumnWidth)
        XCTAssertLessThan(rightColumnWidth, 140)
    }

    @MainActor
    func testInlineCodeAndFencedCodeUseDistinctPresentations() throws {
        let parsed = makeParser().parse(
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
        let multiline = NSAttributedString(
            string: "first line\nsecond line\nthird line",
            attributes: [.font: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)]
        )
        let insets = RichContainerInsets(top: 12, left: 16, bottom: 12, right: 16)
        let measured = RichCodeBlockViewProvider.requiredContentSize(for: multiline, contentInsets: insets)
        let displayed = RichTextView()
        displayed.lineBreakMode = .byClipping
        displayed.attributedText = multiline
        XCTAssertEqual(
            measured.height,
            displayed.sizeThatFits(CGSize(width: 320, height: 100_000)).height + insets.top + insets.bottom
        )
        XCTAssertTrue(rendered.unhandledNodeTypes.isEmpty)
    }

    func testCodeBlockInsideListItemKeepsBlockSpacing() throws {
        let parsed = makeParser().parse(
            "- 使用示例：\n\n  ```swift\n  let value = 42\n  ```",
            documentID: "list-code"
        )
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 320,
            configuration: .standard
        )
        let layout = RichTextLayoutEngine().layout(
            snapshot: rendered.snapshot,
            constrainedTo: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        let label = try XCTUnwrap(layout.textRunBoxes.first)
        let code = try XCTUnwrap(layout.attachmentRunBoxes.first {
            $0.element.reuseIdentifier == RichCodeBlockViewProvider.reuseIdentifier
        })

        XCTAssertEqual(code.frame.minY - label.frame.maxY, RichContentLayoutMetrics().blockSpacing)
    }

    @MainActor
    func testMarkdownEntryPointRendersThroughUnifiedNodeTree() {
        let parsed = makeParser(imageSize: CGSize(width: 24, height: 20)).parse(
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

    func testBuiltInCodeBlockHighlightingReusesLanguageAcrossStreamingNodeStates() throws {
        RichCodeBlockHighlighting.useBuiltIn(theme: .github, maximumCachedCodeBlocks: 8)
        defer { RichCodeBlockHighlighting.unregister() }

        for index in 0..<40 {
            let source = String("let streamingValue = \(index)".prefix(index % 24 + 1))
            let presentation = try XCTUnwrap(RichCodeBlockHighlighting.presentation(
                for: source,
                language: "swift",
                nodeID: "streaming-code-\(index)"
            ))
            XCTAssertEqual(presentation.attributedCode.string, source)
        }
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
        let parsed = makeParser().parse(
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

    private func makeParser(
        imageSize: CGSize = CGSize(width: 24, height: 24)
    ) -> RichMarkdownParser {
        RichMarkdownParser(imageSize: imageSize)
    }

    private func containsImage(_ element: RichElement) -> Bool {
        if element is RichImageElement { return true }
        return (element as? RichContainerElement)?.children.contains(where: containsImage) == true
    }

    private func flattenElements(_ element: RichElement) -> [RichElement] {
        [element] + element.children.flatMap(flattenElements)
    }

    private final class TestImageResolver: RichContentPresentationResolving {
        func imageSource(
            for node: RichContentNode,
            content: RichImageContent
        ) -> RichImageSource? {
            RichImageSource(identifier: content.source, image: UIImage(systemName: "photo"))
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
