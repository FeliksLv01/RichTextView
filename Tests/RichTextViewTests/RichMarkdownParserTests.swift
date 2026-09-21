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
    func testLatexElementsDrawWithoutViewAttachmentsAndKeepLastValidStream() throws {
        let renderer = RichContentRenderer()
        func render(_ latex: String, streaming: Bool = true) -> RichElementSnapshot {
            renderer.render(document: makeParser().parse(
                "Inline \\(x^2 + y^2\\).\n\n$$\n" + latex + "\n$$", documentID: "math"
            ).document, constrainedWidth: 320, configuration: .standard, streaming: streaming).snapshot
        }
        let initial = render("x")
        let formulas = flattenElements(initial.root).compactMap { $0 as? RichLatexElement }
        XCTAssertEqual(formulas.count, 2)
        let block = try XCTUnwrap(formulas.last)
        XCTAssertGreaterThan(block.size.width, 0)
        let layout = RichTextLayoutEngine().layout(snapshot: initial, constrainedTo: CGSize(width: 320, height: 1000))
        XCTAssertTrue(layout.attachmentRunBoxes.isEmpty)
        XCTAssertEqual(layout.textRunBoxes.last?.frame.width, 320)
        XCTAssertEqual(block.copyText, "$$x$$")
        let blockRun = try XCTUnwrap(layout.textRunBoxes.last)
        let height = Int(ceil(blockRun.layout.size.height))
        let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: height, bitsPerComponent: 8,
            bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        blockRun.layout.draw(in: context, canvasHeight: CGFloat(height), origin: .zero, isCancelled: { false })
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let occupiedColumns = (0..<320).filter { x in (0..<height).contains { y in pixels[(y * 320 + x) * 4 + 3] > 0 } }
        let left = try XCTUnwrap(occupiedColumns.first)
        let right = try XCTUnwrap(occupiedColumns.last)
        XCTAssertEqual(Double(left + right) / 2, 160, accuracy: 2)
        let unfinished = render("x\\unknowncommand")
        let retained = try XCTUnwrap(flattenElements(unfinished.root).compactMap { $0 as? RichLatexElement }.last)
        XCTAssertTrue(retained.layout === block.layout)
        XCTAssertEqual(retained.size, block.size)
        let finished = render("x\\frac{1}{2}")
        let updated = try XCTUnwrap(flattenElements(finished.root).compactMap { $0 as? RichLatexElement }.last)
        XCTAssertFalse(updated.layout === block.layout)
        XCTAssertGreaterThan(updated.size.width, block.size.width)
        let invalidFinal = render("x\\frac{", streaming: false)
        XCTAssertEqual(flattenElements(invalidFinal.root).compactMap { $0 as? RichLatexElement }.count, 1)
    }

    @MainActor
    func testStreamingCasesDisplaysRowsBeforeEnvironmentCloses() throws {
        let renderer = RichContentRenderer()
        func formula(_ latex: String, streaming: Bool = true) throws -> RichLatexElement {
            let document = RichContentDocument(id: "preview", children: [
                RichContentNode(id: "formula", type: .math, content: RichMathContent(latex: latex, isBlock: true))
            ])
            let snapshot = renderer.render(document: document, constrainedWidth: 320,
                configuration: .standard, streaming: streaming).snapshot
            return try XCTUnwrap(snapshot.root.children.first as? RichLatexElement)
        }
        let firstRow = #"x_n = \begin{cases} 0, & \text{odd}"#
        let first = try formula(firstRow)
        XCTAssertEqual(first.latex, firstRow)
        XCTAssertEqual(first.copyText, "$$" + firstRow + "$$")
        let secondRow = firstRow + #" \\ n, & \text{even}"#
        let second = try formula(secondRow)
        XCTAssertEqual(second.latex, secondRow)
        XCTAssertGreaterThan(second.size.height, first.size.height)
        let closingCommand = try formula(secondRow + #"\end{cas"#)
        XCTAssertEqual(closingCommand.size, second.size)
        let complete = secondRow + #"\end{cases}"#
        let final = try formula(complete, streaming: false)
        XCTAssertEqual(final.size, second.size)
        let nested = try formula(#"\boxed{\begin{cases} \frac{1}{2}, & \text{odd}"#)
        XCTAssertGreaterThan(nested.size.height, first.size.height)
        XCTAssertNil(RichLatexPreview.complete(#"\begin{cases}x\end{matrix}"#))
        XCTAssertEqual(RichLatexPreview.complete(#"\left\{x"#), #"\left\{x\right."#)
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
        XCTAssertGreaterThan(flatten(updatedTable).count, flatten(initialTable).count)
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
        let highlightedCode = try XCTUnwrap(elements.compactMap { $0 as? RichTextElement }.first {
            $0.attributedText.string == "let value = 42"
        })

        XCTAssertNotNil(inlineCode.attributedText.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(inlineCode.cornerRadius, 4)
        XCTAssertEqual(inlineCode.borderWidth, 1)
        XCTAssertEqual(highlightedCode.copyText, "let value = 42")
        XCTAssertEqual(highlightedCode.maximumNumberOfLines, 15)
        XCTAssertEqual(highlightedCode.lineBreakMode, .byCharWrapping)
        XCTAssertEqual(
            (highlightedCode.attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineBreakMode,
            .byCharWrapping
        )
        XCTAssertTrue(elements.compactMap { $0 as? RichImageElement }.contains {
            $0.actionIdentifier.hasPrefix("copy-code:")
        })
        XCTAssertFalse(elements.contains { $0 is RichAttachmentElement })
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
        let codeBackground = try XCTUnwrap(layout.runBoxes.compactMap { $0 as? RichDecorationRunBox }.first {
            if case .borderedBackground = $0.decoration { return true }
            return false
        })

        XCTAssertEqual(codeBackground.frame.minY - label.frame.maxY, RichContentLayoutMetrics().blockSpacing)
        XCTAssertTrue(layout.attachmentRunBoxes.isEmpty)
    }

    @MainActor
    func testCodeBlockCanRestoreHorizontalScrolling() throws {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let configuration = RichContentRenderingConfiguration(
            font: font,
            lineHeight: font.lineHeight,
            textColor: .label,
            secondaryTextColor: .secondaryLabel,
            linkColor: .link,
            currentMentionTextColor: .label,
            currentMentionBackgroundColor: .tertiarySystemFill,
            contrastBackgroundColor: .secondarySystemBackground,
            blockQuoteColor: .separator,
            codeBackgroundColor: .secondarySystemBackground,
            codeBlockOverflowBehavior: .horizontalScroll,
            highlightTextColor: .label,
            highlightBackgroundColor: .systemYellow
        )
        let parsed = makeParser().parse(
            "```swift\nlet value = aVeryLongExpressionThatNeedsHorizontalScrolling\n```",
            documentID: "scrolling-code"
        )
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 120,
            configuration: configuration
        )
        let attachment = try XCTUnwrap(flattenElements(rendered.snapshot.root).compactMap {
            $0 as? RichAttachmentElement
        }.first)

        XCTAssertEqual(configuration.codeBlockOverflowBehavior, .horizontalScroll)
        XCTAssertEqual(attachment.reuseIdentifier, RichCodeBlockViewProvider.reuseIdentifier)
        XCTAssertTrue(attachment.provider is RichCodeBlockViewProvider)
    }

    @MainActor
    func testLongCodeBlockFollowsTailWhileStreamingAndReturnsToHeadWhenComplete() throws {
        let lines = (0..<20).map { "line \($0)" }.joined(separator: "\n")
        let parser = makeParser()
        let renderer = RichContentRenderer()
        let open = parser.parse("```swift\n" + lines, documentID: "stream-code", streaming: true)
        let openContent = try XCTUnwrap(flatten(open.document.root).compactMap {
            $0.content(as: RichCodeBlockContent.self)
        }.last)
        let openSnapshot = renderer.render(
            document: open.document,
            constrainedWidth: 320,
            configuration: .standard,
            streaming: true
        ).snapshot
        let openLayout = RichTextLayoutEngine().layout(
            snapshot: openSnapshot,
            constrainedTo: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        let streamedCode = try XCTUnwrap(openLayout.textRunBoxes.first { $0.text.string.contains("line 19") })

        XCTAssertTrue(openContent.isStreaming)
        XCTAssertFalse(streamedCode.text.string.contains("line 0"))
        XCTAssertEqual(streamedCode.layout.lines.count, 15)
        XCTAssertTrue(openLayout.attachmentRunBoxes.isEmpty)

        let closed = parser.parse("```swift\n" + lines + "\n```", documentID: "stream-code", streaming: true)
        let closedContent = try XCTUnwrap(flatten(closed.document.root).compactMap {
            $0.content(as: RichCodeBlockContent.self)
        }.last)
        let closedSnapshot = renderer.render(
            document: closed.document,
            constrainedWidth: 320,
            configuration: .standard,
            streaming: true
        ).snapshot
        let closedLayout = RichTextLayoutEngine().layout(
            snapshot: closedSnapshot,
            constrainedTo: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        let completedCode = try XCTUnwrap(closedLayout.textRunBoxes.first { $0.text.string.contains("line 0") })
        let viewAll = try XCTUnwrap(closedLayout.textRunBoxes.first {
            $0.segments.contains { $0.actionIdentifier?.hasPrefix("code-block:") == true }
        })

        XCTAssertFalse(closedContent.isStreaming)
        XCTAssertEqual(completedCode.layout.lines.count, 15)
        XCTAssertTrue(viewAll.segments.first?.actionIdentifier?.hasPrefix("code-block:") == true)
        XCTAssertTrue(closedLayout.runBoxes.contains {
            guard let decoration = $0 as? RichDecorationRunBox,
                  case .verticalGradient = decoration.decoration else { return false }
            return true
        })

        let longLine = String(repeating: "abcdefghij", count: 20)
        let wrapped = parser.parse("```text\n" + longLine + "\n```", documentID: "wrapped-code")
        let wrappedSnapshot = renderer.render(
            document: wrapped.document,
            constrainedWidth: 120,
            configuration: .standard
        ).snapshot
        let wrappedLayout = RichTextLayoutEngine().layout(
            snapshot: wrappedSnapshot,
            constrainedTo: CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude)
        )
        let wrappedCode = try XCTUnwrap(wrappedLayout.textRunBoxes.first { $0.text.string == longLine })
        XCTAssertGreaterThan(wrappedCode.layout.lines.count, 1)
        XCTAssertLessThanOrEqual(wrappedCode.frame.maxX, 120)
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
        let inputs = false
        func imageSource(
            for node: RichContentNode,
            content: RichImageContent
        ) -> RichImageSource? {
            RichImageSource(identifier: content.source, image: UIImage(systemName: "photo"))
        }
    }

    private final class TestCodeResolver: RichContentPresentationResolving {
        let inputs = false
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
