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
        func imageSource(
            for node: RichContentNode,
            content: RichImageContent
        ) -> RichImageSource? {
            RichImageSource(identifier: content.source, image: UIImage(systemName: "photo"))
        }
    }

    private final class TestCustomNodeBuilder: RichContentElementBuilding {
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
                display: .block,
                revision: RichElementRevision(layout: node.revision.layout, display: node.revision.display)
            )
        }
    }
}
