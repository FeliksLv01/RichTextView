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

    private func makeView() -> RichTextView {
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 1_000))
        view.laysOutAsynchronously = false
        return view
    }
}
