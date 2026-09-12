import XCTest
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
    func testMarkdownEntryPointRendersThroughUnifiedNodeTree() {
        let parsed = RichMarkdownParser().parse("# Title\n\nMarkdown body", documentID: "markdown")
        let rendered = RichContentRenderer().render(
            document: parsed.document,
            constrainedWidth: 320,
            configuration: .standard
        )
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 1_000))
        view.laysOutAsynchronously = false

        view.apply(rendered.snapshot)

        XCTAssertTrue(rendered.unhandledNodeTypes.isEmpty)
        XCTAssertEqual(view.currentSnapshot?.root.id, "markdown")
        XCTAssertGreaterThan(view.currentLayout?.contentSize.height ?? 0, 0)
    }

    private func flatten(_ node: RichContentNode) -> [RichContentNode] {
        [node] + node.children.flatMap(flatten)
    }
}
