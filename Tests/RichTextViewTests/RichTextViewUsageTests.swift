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
            root: RichContentNode(
                id: "root",
                type: .root,
                children: [
                    RichContentNode(
                        id: "paragraph",
                        type: .paragraph,
                        children: [
                            RichContentNode(
                                id: "text",
                                type: .text,
                                content: RichTextContent(text: "Node tree")
                            )
                        ]
                    )
                ]
            )
        )
        let result = RichContentRenderer().render(
            document: document,
            constrainedWidth: 320,
            configuration: .standard
        )
        let view = makeView()

        view.apply(result.snapshot)

        XCTAssertTrue(result.unhandledNodeTypes.isEmpty)
        XCTAssertEqual(view.currentSnapshot?.root.id, "root")
        XCTAssertGreaterThan(view.currentLayout?.contentSize.height ?? 0, 0)
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
                                content: RichImageContent(source: "example://image", title: "Image")
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
        XCTAssertTrue(paragraph.children[1] is RichImageElement)
        XCTAssertTrue(result.unhandledNodeTypes.isEmpty)
    }

    private func makeView() -> RichTextView {
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 1_000))
        view.laysOutAsynchronously = false
        return view
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
}
