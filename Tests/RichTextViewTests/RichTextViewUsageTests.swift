import XCTest
import UIKit
@testable import RichTextView

@MainActor
final class RichTextViewUsageTests: XCTestCase {
    func testStringEntryPointProducesLayout() {
        let view = makeView()

        view.text = "Plain text"

        XCTAssertEqual(view.text, "Plain text")
        XCTAssertNotNil(view.currentSnapshot)
        XCTAssertGreaterThan(view.currentLayout?.contentSize.height ?? 0, 0)
    }

    func testAsyncUpdatesPreserveRenderedContentByDefault() {
        let view = makeView()

        XCTAssertTrue(view.preservesRenderedContentDuringAsyncUpdates)
    }

    func testStreamingReusesUnchangedTilesAndInvalidatesAppearance() throws {
        let view = makeView()
        let layer = try XCTUnwrap(view.layer as? RichRenderLayer)
        layer.maximumTileSize = CGSize(width: 320, height: 100)
        let engine = RichTextLayoutEngine()
        func update(_ tail: String) {
            let document = RichContentDocument(id: "stream", children: [
                .paragraph(id: "fixed", text: String(repeating: "Stable paragraph. ", count: 150)),
                .paragraph(id: "tail", text: tail)
            ])
            let snapshot = RichContentRenderer().render(document: document, constrainedWidth: 320, configuration: .standard).snapshot
            let layout = engine.layout(snapshot: snapshot, constrainedTo: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
            view.frame.size = CGSize(width: 320, height: layout.contentSize.height)
            view.apply(snapshot, layout: layout)
            layer.display()
        }
        update("First")
        let oldTiles = try XCTUnwrap(layer.sublayers?.first?.sublayers)
        XCTAssertGreaterThan(oldTiles.count, 3)
        update("First plus more streamed text")
        let newTiles = try XCTUnwrap(layer.sublayers?.first?.sublayers)
        let reused = zip(oldTiles, newTiles).filter { $0 === $1 }.count
        XCTAssertGreaterThanOrEqual(reused, newTiles.count - 2)
        print("Streaming tile reuse: \(reused)/\(newTiles.count)")
        XCTAssertTrue(oldTiles[0] === newTiles[0], "Completed text must keep its layer and bitmap")
        XCTAssertFalse(oldTiles.last === newTiles.last)
        let light = view.newRenderDisplayTask()
        light.traits = UITraitCollection(userInterfaceStyle: .light)
        let dark = view.newRenderDisplayTask()
        dark.traits = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(dark.unchangedPrefixHeight(comparedTo: light), 0)
        let container = newTiles[0].superlayer
        view.prepareForReuse()
        XCTAssertNil(container?.superlayer)
    }

    func testStreamingFadeOnlyIncludesAppendedTextAndRejectsRewrites() throws {
        let view = makeView()
        view.text = "Hello"
        let old = view.newRenderDisplayTask()
        view.text = "Hello world"
        let next = view.newRenderDisplayTask()
        let rects = try XCTUnwrap(next.appendedTextRects(comparedTo: old))
        XCTAssertEqual(rects.count, 1)
        let run = try XCTUnwrap(next.layout?.textRunBoxes.first)
        let prefix = try XCTUnwrap(run.layout.selectionRects(for: NSRange(location: 0, length: 5)).first)
        XCTAssertTrue(rects.allSatisfy { $0.minX >= prefix.maxX })
        view.text = "Rewritten answer"
        XCTAssertNil(view.newRenderDisplayTask().appendedTextRects(comparedTo: next))
    }

    func testAsyncTilesKeepOldGenerationUntilReadyAndDiscardCancelledWork() async throws {
        let layer = RichRenderLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 250)
        layer.maximumTileSize = CGSize(width: 100, height: 100)
        let delegate = StreamingLayerDelegate()
        layer.richDisplayDelegate = delegate
        delegate.task.display = { context, size, _ in context.fill(CGRect(origin: .zero, size: size)) }
        layer.display()
        let old = try XCTUnwrap(layer.sublayers?.first)
        let started = expectation(description: "Background drawing starts")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        delegate.task = RichRenderLayerDisplayTask()
        delegate.task.display = { _, _, cancelled in
            if !cancelled() {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 3)
            }
        }
        layer.displaysAsynchronously = true
        layer.setNeedsDisplay()
        layer.display()
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(layer.sublayers?.first === old, "Async rendering must not clear the visible tiles")
        layer.clearDisplayContents()
        gate.signal()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(layer.sublayers?.isEmpty ?? true, "A reused view must reject stale rendering results")
    }

    func testViewportInstallsVisibleTileAsynchronously() async throws {
        let layer = RichRenderLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 1_000)
        layer.maximumTileSize = CGSize(width: 100, height: 100)
        layer.displaysAsynchronously = true
        let delegate = StreamingLayerDelegate()
        layer.richDisplayDelegate = delegate
        delegate.task.layout = RichTextLayout(
            rootElementID: "root",
            constrainedSize: layer.bounds.size,
            contentSize: layer.bounds.size,
            runBoxes: [],
            lines: [RichLineBox(frame: CGRect(x: 0, y: 480, width: 100, height: 40), runBoxIDs: [])]
        )
        let started = expectation(description: "Viewport drawing starts")
        let finished = expectation(description: "Viewport drawing finishes")
        started.expectedFulfillmentCount = 2
        finished.expectedFulfillmentCount = 2
        delegate.task.display = { context, size, _ in
            started.fulfill()
            Thread.sleep(forTimeInterval: 0.2)
            context.fill(CGRect(origin: .zero, size: size))
            finished.fulfill()
        }

        layer.updateVisibleRect(CGRect(x: 0, y: 400, width: 100, height: 100), viewportHeight: 100)
        let begin = CACurrentMediaTime()
        layer.display()
        XCTAssertLessThan(CACurrentMediaTime() - begin, 0.1, "Viewport drawing must not block the main thread")
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(layer.sublayers?.isEmpty ?? true)
        await fulfillment(of: [finished], timeout: 2)
        try await Task.sleep(nanoseconds: 50_000_000)
        let tiles = try XCTUnwrap(layer.sublayers?.first?.sublayers)
        XCTAssertTrue(tiles.contains { $0.frame.intersects(CGRect(x: 0, y: 400, width: 100, height: 100)) })
        XCTAssertTrue(tiles.contains { $0.frame.minY == 500 })
        XCTAssertEqual(tiles.count, 2)
    }

    func testViewportThresholdUsesAvailableHeightInsteadOfWidth() {
        let layer = RichRenderLayer()
        layer.maximumTileSize = CGSize(width: 1_024, height: 1_024)
        layer.bounds = CGRect(x: 0, y: 0, width: 1_200, height: 1_100)

        layer.updateVisibleRect(layer.bounds, viewportHeight: 1_200)
        XCTAssertFalse(layer.needsViewport)

        layer.bounds.size.height = 1_300
        layer.updateVisibleRect(CGRect(x: 0, y: 0, width: 1_200, height: 1_200), viewportHeight: 1_200)
        XCTAssertTrue(layer.needsViewport)
    }

    func testAttributedStringEntryPointPreservesContentAndProducesLayout() {
        let source = NSAttributedString(
            string: "Attributed text",
            attributes: [.font: UIFont.boldSystemFont(ofSize: 18)]
        )
        let view = makeView()

        view.attributedText = source

        XCTAssertEqual(view.attributedText?.string, source.string)
        XCTAssertNotNil(view.currentSnapshot)
        XCTAssertGreaterThan(view.currentLayout?.contentSize.height ?? 0, 0)
    }

    func testDocumentEntryPointRendersThroughUnifiedNodeTree() {
        let document = RichContentDocument(
            id: "root",
            children: [.paragraph(id: "paragraph", text: "Node tree")]
        )
        let view = makeView()

        view.setContent(document)

        XCTAssertEqual(view.currentSnapshot?.root.id, "root")
        XCTAssertGreaterThan(view.currentLayout?.contentSize.height ?? 0, 0)
    }

    func testDocumentEntryPointDefersRenderingUntilWidthIsAvailable() {
        let view = RichTextView()
        view.laysOutAsynchronously = false

        view.setContent(RichContentDocument(
            id: "root",
            children: [.paragraph(id: "paragraph", text: "Deferred node tree")]
        ))

        XCTAssertNil(view.currentSnapshot)

        view.frame.size = CGSize(width: 240, height: 1_000)
        view.layoutIfNeeded()

        XCTAssertEqual(view.currentSnapshot?.root.id, "root")
        XCTAssertEqual(view.currentLayout?.constrainedSize.width, 240)
    }

    func testDocumentSupportsInlineImageBetweenTextNodes() throws {
        let document = RichContentDocument(
            root: RichContentNode(
                id: "root",
                type: .root,
                children: [
                    RichContentNode(
                        id: "paragraph",
                        type: .paragraph,
                        children: [
                            RichContentNode(id: "before", type: .text, content: RichTextContent(text: "Before ")),
                            RichContentNode(
                                id: "image",
                                type: .image,
                                content: RichImageContent(
                                    source: "example://image",
                                    title: "Image",
                                    size: CGSize(width: 24, height: 20)
                                )
                            ),
                            RichContentNode(id: "after", type: .text, content: RichTextContent(text: " after"))
                        ]
                    )
                ]
            )
        )
        let result = RichContentRenderer().render(
            document: document,
            constrainedWidth: 320,
            configuration: .standard,
            resolver: TestImageResolver()
        )
        let paragraph = try XCTUnwrap(result.snapshot.root.children.first as? RichContainerElement)

        XCTAssertEqual(paragraph.children.count, 3)
        let image = try XCTUnwrap(paragraph.children.dropFirst().first as? RichImageElement)
        XCTAssertEqual(image.size, CGSize(width: 24, height: 20))
        XCTAssertTrue(result.unhandledNodeTypes.isEmpty)
    }

    func testImageNodeCanBeInsertedAfterAsyncSizeResolution() async throws {
        let view = makeView()
        let initialDocument = RichContentDocument(
            id: "async-image-document",
            children: [.paragraph(
                id: "paragraph",
                children: [
                    .text(id: "before", "Before "),
                    .text(id: "after", "after")
                ]
            )]
        )
        view.setContent(initialDocument, resolver: TestImageResolver())

        XCTAssertFalse(containsImage(in: try XCTUnwrap(view.currentSnapshot?.root)))

        let updatedDocument = await Task.detached {
            RichContentDocument(
                id: "async-image-document",
                children: [.paragraph(
                    id: "paragraph",
                    children: [
                        .text(id: "before", "Before "),
                        RichContentNode(
                            id: "loaded-image",
                            type: .image,
                            content: RichImageContent(
                                source: "example://loaded-image",
                                title: "Loaded image",
                                size: CGSize(width: 80, height: 45)
                            )
                        ),
                        .text(id: "after", "after")
                    ]
                )]
            )
        }.value
        view.setContent(updatedDocument, resolver: TestImageResolver())

        let root = try XCTUnwrap(view.currentSnapshot?.root)
        let image = try XCTUnwrap(flatten(root).compactMap { $0 as? RichImageElement }.first)
        XCTAssertEqual(image.id, "loaded-image")
        XCTAssertEqual(image.size, CGSize(width: 80, height: 45))
    }

    func testTextNodeSupportsSemanticForegroundAndBackgroundColors() throws {
        let document = RichContentDocument(
            root: RichContentNode(
                id: "root",
                type: .root,
                children: [RichContentNode(
                    id: "text",
                    type: .text,
                    content: RichTextContent(
                        text: "Styled",
                        style: RichTextStyle(
                            foregroundColor: "systemOrange",
                            backgroundColor: "secondarySystemFill"
                        )
                    )
                )]
            )
        )
        let result = RichContentRenderer().render(
            document: document,
            constrainedWidth: 320,
            configuration: .standard
        )
        let text = try XCTUnwrap(result.snapshot.root.children.first as? RichTextElement)

        XCTAssertEqual(
            text.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
            UIColor.systemOrange
        )
        XCTAssertEqual(
            text.attributedText.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? UIColor,
            UIColor.secondarySystemFill
        )
    }

    func testCustomNodeTypeCanBeRegisteredWithoutChangingTheLibrary() throws {
        let nodeType = RichContentNodeType(rawValue: "test-answer-card")
        let document = RichContentDocument(root: RichContentNode(
            id: "root",
            type: .root,
            children: [RichContentNode(id: "card", type: nodeType)]
        ))
        let registry = RichContentElementBuilderRegistry.standard.registering(
            TestCustomNodeBuilder(nodeType: nodeType)
        )
        let rendered = RichContentRenderer(registry: registry).render(
            document: document,
            constrainedWidth: 320,
            configuration: .standard
        )
        let element = try XCTUnwrap(rendered.snapshot.root.children.first as? RichTextElement)

        XCTAssertEqual(element.attributedText.string, "Custom answer card")
        XCTAssertTrue(rendered.unhandledNodeTypes.isEmpty)
    }

    private func makeView() -> RichTextView {
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 1_000))
        view.laysOutAsynchronously = false
        return view
    }

    private func containsImage(in element: RichElement) -> Bool {
        flatten(element).contains { $0 is RichImageElement }
    }

    private func flatten(_ element: RichElement) -> [RichElement] {
        [element] + element.children.flatMap(flatten)
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

    private final class TestCustomNodeBuilder: RichContentElementBuilding {
        let inputs = false
        let nodeType: RichContentNodeType

        init(nodeType: RichContentNodeType) {
            self.nodeType = nodeType
        }

        func build(
            node: RichContentNode,
            children: [RichElement],
            context: RichContentRenderContext
        ) -> RichElement? {
            RichTextElement(
                id: node.id,
                attributedText: NSAttributedString(string: "Custom answer card"),
                display: .block
            )
        }
    }
}

@MainActor
private final class StreamingLayerDelegate: RichRenderLayerDelegate {
    var task = RichRenderLayerDisplayTask()
    func newRenderDisplayTask() -> RichRenderLayerDisplayTask { task }
}
