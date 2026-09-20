import XCTest
@testable import RichTextView

final class RichElementSnapshotTests: XCTestCase {
    func testUpdatePreservesUnchangedSiblings() {
        let first = text(id: "first", value: "A")
        let second = text(id: "second", value: "B")
        let snapshot = RichElementSnapshot(root: RichContainerElement(
            id: "root",
            children: [first, second]
        ))

        let updatedFirst = text(id: "first", value: "AA")
        let updated = snapshot.applying([.update(updatedFirst)])

        XCTAssertTrue(updated.root.children[0] === updatedFirst)
        XCTAssertTrue(updated.root.children[1] === second)
    }

    func testInsertAndRemoveOnlyRebuildAncestorPath() {
        let nestedChild = text(id: "nested-child", value: "A")
        let nested = RichContainerElement(id: "nested", children: [nestedChild])
        let sibling = text(id: "sibling", value: "B")
        let snapshot = RichElementSnapshot(root: RichContainerElement(
            id: "root",
            children: [nested, sibling]
        ))

        let inserted = text(id: "inserted", value: "C")
        let updated = snapshot.applying([.insert(inserted, parentID: "nested", index: 1)])
        let removed = updated.applying([.remove(id: "nested-child")])

        let updatedNested = try? XCTUnwrap(removed.element(withID: "nested") as? RichContainerElement)
        XCTAssertEqual(updatedNested?.children.map(\.id), ["inserted"])
        XCTAssertTrue(removed.element(withID: "sibling") === sibling)
    }

    func testRenderTreeReusesStableObjectsAndMarksOnlyChangedBranchDirty() throws {
        let first = text(id: "first", value: "A")
        let second = text(id: "second", value: "B")
        let initial = RichElementSnapshot(root: RichContainerElement(
            id: "root",
            children: [first, second]
        ))
        let tree = RichRenderTree(snapshot: initial)
        tree.markClean()
        let originalFirst = tree.root.children[0]
        let originalSecond = tree.root.children[1]

        let updated = initial.applying([.update(text(id: "first", value: "AA"))])
        tree.reconcile(snapshot: updated)

        XCTAssertTrue(tree.root.children[0] === originalFirst)
        XCTAssertTrue(tree.root.children[1] === originalSecond)
        XCTAssertTrue(tree.root.children[0].dirtyState.contains(.layout))
        XCTAssertTrue(tree.root.children[1].dirtyState.isEmpty)
    }

    private func text(id: String, value: String) -> RichTextElement {
        RichTextElement(
            id: id,
            attributedText: NSAttributedString(string: value)
        )
    }
}
