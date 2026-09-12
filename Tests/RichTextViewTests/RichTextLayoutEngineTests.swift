import UIKit
import XCTest
@testable import RichTextView

final class RichTextLayoutEngineTests: XCTestCase {
    func testImageAspectFitPreservesSourceRatioInsideContentInsets() {
        let fitted = RichImageDrawing.fittedRect(
            imageSize: CGSize(width: 200, height: 100),
            in: CGRect(x: 10, y: 20, width: 100, height: 100),
            contentInsets: UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 5),
            contentMode: .scaleAspectFit
        )

        XCTAssertEqual(fitted, CGRect(x: 15, y: 47.5, width: 90, height: 45))
        XCTAssertEqual(fitted.width / fitted.height, 2)
    }

    func testInlineTextBadgeBaselineOffsetMovesRunMetricsTogether() {
        let attributedText = NSAttributedString(string: "Badge", attributes: [
            .font: UIFont.systemFont(ofSize: 14)
        ])
        let natural = RichInlineTextBadge(
            attributedText: attributedText,
            contentInsets: UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4),
            outerInsets: .zero,
            cornerRadius: 4,
            baselineOffset: 0
        )
        let shifted = RichInlineTextBadge(
            attributedText: attributedText,
            contentInsets: UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4),
            outerInsets: .zero,
            cornerRadius: 4,
            baselineOffset: 3
        )

        XCTAssertEqual(shifted.ascent - natural.ascent, 3, accuracy: 0.01)
        XCTAssertEqual(natural.descent - shifted.descent, 3, accuracy: 0.01)
        XCTAssertEqual(shifted.size.height, natural.size.height, accuracy: 0.01)
    }

    func testLayoutEngineDoesNotRetainSnapshotTree() {
        let engine = RichTextLayoutEngine()
        weak var rootReference: RichContainerElement?

        autoreleasepool {
            let root = RichContainerElement(
                id: "transient-root",
                children: [RichTextElement(
                    id: "transient-text",
                    attributedText: NSAttributedString(string: "transient")
                )]
            )
            rootReference = root
            _ = engine.layout(
                snapshot: RichElementSnapshot(root: root),
                constrainedTo: CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude)
            )
        }

        XCTAssertNil(rootReference)
    }

    func testInlineTextBadgeKeepsAtomicActionAndCopySemantics() throws {
        let badge = RichTextBadgeElement(
            id: "mention-self",
            text: "@吕良",
            font: UIFont.systemFont(ofSize: 16),
            foregroundColor: .white,
            backgroundColor: .systemBlue,
            contentInsets: UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6),
            outerInsets: UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4),
            cornerRadius: 11,
            actionIdentifier: "mention:contact-id"
        )
        let badgeWithoutOuterSpacing = RichTextBadgeElement(
            id: "mention-self-without-spacing",
            text: "@吕良",
            font: UIFont.systemFont(ofSize: 16),
            foregroundColor: .white,
            backgroundColor: .systemBlue,
            contentInsets: UIEdgeInsets(top: 1, left: 6, bottom: 1, right: 6),
            cornerRadius: 11,
            actionIdentifier: "mention:contact-id"
        )
        let layout = RichTextLayoutEngine().layout(
            snapshot: RichElementSnapshot(root: RichContainerElement(id: "root", children: [badge])),
            constrainedTo: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        )
        let layoutWithoutOuterSpacing = RichTextLayoutEngine().layout(
            snapshot: RichElementSnapshot(root: RichContainerElement(
                id: "root-without-spacing",
                children: [badgeWithoutOuterSpacing]
            )),
            constrainedTo: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        )

        let runBox = try XCTUnwrap(layout.textRunBoxes.first)
        let runBoxWithoutOuterSpacing = try XCTUnwrap(layoutWithoutOuterSpacing.textRunBoxes.first)
        let segment = try XCTUnwrap(runBox.segments.first)
        XCTAssertEqual(runBox.text.string, "\u{FFFC}")
        XCTAssertEqual(segment.range, NSRange(location: 0, length: 1))
        XCTAssertEqual(segment.copyText, "@吕良")
        XCTAssertEqual(segment.actionIdentifier, "mention:contact-id")
        XCTAssertEqual(
            runBox.frame.width - runBoxWithoutOuterSpacing.frame.width,
            8,
            accuracy: 0.01
        )
        XCTAssertGreaterThan(runBox.frame.width, ("@吕良" as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 16)
        ]).width)
    }

    func testWordJoinerKeepsBadgeAndTrailingImageOnSameLine() throws {
        let font = UIFont.systemFont(ofSize: 16)
        let badge = RichTextBadgeElement(
            id: "mention",
            text: "@小明",
            font: font,
            foregroundColor: .systemBlue,
            backgroundColor: .clear,
            contentInsets: .zero,
            cornerRadius: 0,
            actionIdentifier: "mention:contact-id"
        )
        let joiner = RichTextElement(
            id: "joiner",
            attributedText: NSAttributedString(string: "\u{2060}"),
            copyText: ""
        )
        let marker = RichImageElement(
            id: "read-status",
            source: RichImageSource(identifier: "read", image: nil),
            size: CGSize(width: 18, height: 24),
            font: font,
            actionIdentifier: "mention:contact-id"
        )
        let group = RichContainerElement(
            id: "mention-group",
            children: [badge, joiner, marker],
            display: .inline
        )
        let groupLayout = RichTextLayoutEngine().layout(
            snapshot: RichElementSnapshot(root: group),
            constrainedTo: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        )
        let constrainedWidth = try XCTUnwrap(groupLayout.textRunBoxes.first?.frame.width) + 1
        let root = RichContainerElement(
            id: "root",
            children: [
                RichTextElement(id: "prefix", attributedText: NSAttributedString(string: "前缀")),
                group,
            ]
        )
        let layout = RichTextLayoutEngine().layout(
            snapshot: RichElementSnapshot(root: root),
            constrainedTo: CGSize(width: constrainedWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        let runBox = try XCTUnwrap(layout.textRunBoxes.first)
        let badgeRange = try XCTUnwrap(runBox.segments.first { $0.elementID == "mention" }?.range)
        let markerRange = try XCTUnwrap(runBox.segments.first { $0.elementID == "read-status" }?.range)
        let badgeLine = runBox.layout.lines.firstIndex { NSIntersectionRange($0.range, badgeRange).length > 0 }
        let markerLine = runBox.layout.lines.firstIndex { NSIntersectionRange($0.range, markerRange).length > 0 }

        XCTAssertGreaterThan(runBox.layout.lines.count, 1)
        XCTAssertEqual(badgeLine, markerLine)
        XCTAssertEqual(
            runBox.segments.first { $0.elementID == "read-status" }?.actionIdentifier,
            "mention:contact-id"
        )
    }

    func testTextAndAttachmentFramesAreProducedBeforeViewsExist() async {
        let provider = await MainActor.run { CountingAttachmentProvider() }
        let text = RichTextElement(
            id: "text",
            attributedText: NSAttributedString(
                string: "Hello rich view",
                attributes: [.font: UIFont.systemFont(ofSize: 16)]
            )
        )
        let attachment = RichAttachmentElement(
            id: "attachment",
            metrics: RichAttachmentMetrics(
                size: CGSize(width: 100, height: 40),
                padding: UIEdgeInsets(top: 4, left: 6, bottom: 8, right: 10)
            ),
            reuseIdentifier: "attachment",
            provider: provider
        )
        let snapshot = RichElementSnapshot(root: RichContainerElement(
            id: "root",
            children: [text, attachment],
            spacing: 5
        ))

        let layout = RichTextLayoutEngine().layout(
            snapshot: snapshot,
            constrainedTo: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        )

        XCTAssertEqual(layout.textRunBoxes.count, 1)
        XCTAssertEqual(layout.attachmentRunBoxes.count, 1)
        XCTAssertEqual(layout.attachmentRunBoxes[0].frame.size, CGSize(width: 116, height: 52))
        XCTAssertEqual(layout.attachmentRunBoxes[0].contentFrame.size, CGSize(width: 100, height: 40))
        let makeCount = await MainActor.run { provider.makeCount }
        XCTAssertEqual(makeCount, 0)
    }

    func testDisplayOnlyRevisionKeepsGeometry() {
        let engine = RichTextLayoutEngine()
        let first = snapshot(displayRevision: 0)
        let second = snapshot(displayRevision: 1)

        let firstLayout = engine.layout(
            snapshot: first,
            constrainedTo: CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude)
        )
        let secondLayout = engine.layout(
            snapshot: second,
            constrainedTo: CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude)
        )

        XCTAssertEqual(firstLayout.contentSize, secondLayout.contentSize)
        XCTAssertEqual(firstLayout.textRunBoxes.first?.frame, secondLayout.textRunBoxes.first?.frame)
    }

    func testTextCacheDoesNotReuseLayoutAcrossDifferentAttributes() throws {
        let engine = RichTextLayoutEngine()
        let normalText = NSAttributedString(
            string: "search result",
            attributes: [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.label
            ]
        )
        let highlightedText = NSMutableAttributedString(attributedString: normalText)
        highlightedText.addAttributes(
            [
                .foregroundColor: UIColor.systemBlue,
                .backgroundColor: UIColor.systemBlue.withAlphaComponent(0.2)
            ],
            range: NSRange(location: 0, length: 6)
        )

        let normalLayout = engine.layout(
            snapshot: textSnapshot(normalText),
            constrainedTo: CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude)
        )
        let highlightedLayout = engine.layout(
            snapshot: textSnapshot(highlightedText),
            constrainedTo: CGSize(width: 160, height: CGFloat.greatestFiniteMagnitude)
        )

        let normalRun = try XCTUnwrap(normalLayout.textRunBoxes.first)
        let highlightedRun = try XCTUnwrap(highlightedLayout.textRunBoxes.first)
        XCTAssertNil(normalRun.text.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(
            highlightedRun.text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
            UIColor.systemBlue
        )
        XCTAssertNotNil(highlightedRun.text.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    @MainActor
    func testSelectableAttachmentOccupiesStableSelectionRange() throws {
        let provider = CountingAttachmentProvider()
        let first = RichTextElement(id: "first", attributedText: NSAttributedString(string: "A"))
        let attachment = RichAttachmentElement(
            id: "image",
            metrics: RichAttachmentMetrics(size: CGSize(width: 40, height: 40)),
            reuseIdentifier: "image",
            provider: provider,
            isSelectable: true
        )
        let last = RichTextElement(id: "last", attributedText: NSAttributedString(string: "B"))
        let layout = RichTextLayoutEngine().layout(
            snapshot: RichElementSnapshot(root: RichContainerElement(
                id: "root",
                children: [first, attachment, last]
            )),
            constrainedTo: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
        )

        XCTAssertEqual(try XCTUnwrap(layout.textRunBoxes.first).globalRange, NSRange(location: 0, length: 1))
        XCTAssertEqual(try XCTUnwrap(layout.attachmentRunBoxes.first).globalRange, NSRange(location: 2, length: 1))
        XCTAssertEqual(try XCTUnwrap(layout.textRunBoxes.last).globalRange, NSRange(location: 4, length: 1))
    }

    @MainActor
    func testAttachmentPoolSurvivesHostCellReuse() {
        let hostView = UIView()
        let manager = RichAttachmentManager(hostView: hostView, poolCapacityPerIdentifier: 1)
        let provider = CountingAttachmentProvider()
        manager.apply([attachmentRunBox(id: "first", provider: provider)])
        manager.prepareForReuse()
        manager.apply([attachmentRunBox(id: "second", provider: provider)])

        XCTAssertEqual(provider.makeCount, 1)
        XCTAssertEqual(provider.updateCount, 2)
        XCTAssertEqual(hostView.subviews.count, 1)
    }

    func testCoreTextLayoutSharesGeometryForSizingHitTestingAndSelection() throws {
        let text = NSAttributedString(
            string: "hello rich view selection",
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        let layout = try XCTUnwrap(RichCoreTextLayout(attributedText: text, constrainedWidth: 90))

        XCTAssertGreaterThan(layout.size.height, 16)
        XCTAssertGreaterThan(layout.lines.count, 1)
        let firstLine = try XCTUnwrap(layout.lines.first)
        let position = try XCTUnwrap(layout.closestPosition(to: CGPoint(
            x: firstLine.frame.minX + 2,
            y: firstLine.frame.midY
        )))
        let wordRange = try XCTUnwrap(layout.characterRange(at: CGPoint(
            x: firstLine.frame.minX + 2,
            y: firstLine.frame.midY
        )))
        let rects = layout.selectionRects(for: wordRange)

        XCTAssertGreaterThanOrEqual(position, 0)
        XCTAssertEqual((text.string as NSString).substring(with: wordRange), "hello")
        XCTAssertFalse(rects.isEmpty)
    }

    func testMinimumLineHeightDoesNotClipLargerHeadingFont() throws {
        let font = UIFont.boldSystemFont(ofSize: 28)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 17
        let text = NSAttributedString(
            string: "Streaming answer",
            attributes: [.font: font, .paragraphStyle: paragraph]
        )

        let layout = try XCTUnwrap(RichCoreTextLayout(attributedText: text, constrainedWidth: 320))
        let line = try XCTUnwrap(layout.lines.first)

        XCTAssertGreaterThanOrEqual(line.frame.height, font.ascender - font.descender)
        XCTAssertGreaterThanOrEqual(layout.size.height, line.frame.maxY)
    }

    func testTallInlineImageExpandsItsLineWithoutOverlappingPreviousLine() throws {
        let font = UIFont.systemFont(ofSize: 17)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = font.lineHeight
        let text = NSMutableAttributedString(
            string: "inline code followed by image ",
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        let imageLocation = text.length
        text.append(RichInlineRunFactory.image(
            identifier: "large-inline-image",
            image: nil,
            size: CGSize(width: 64, height: 28),
            contentInsets: .zero,
            font: font,
            contentMode: .scaleAspectFit,
            tintColor: nil
        ))

        let layout = try XCTUnwrap(RichCoreTextLayout(attributedText: text, constrainedWidth: 190))
        let imageFrame = try XCTUnwrap(layout.inlineRunRect(at: imageLocation))
        let imageLine = try XCTUnwrap(layout.lines.first {
            NSLocationInRange(imageLocation, $0.range)
        })

        XCTAssertGreaterThanOrEqual(imageLine.frame.height, 28)
        XCTAssertGreaterThanOrEqual(imageFrame.minY, imageLine.frame.minY)
        XCTAssertLessThanOrEqual(imageFrame.maxY, imageLine.frame.maxY + 0.5)
        for pair in zip(layout.lines, layout.lines.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.frame.maxY, pair.1.frame.minY + 0.5)
        }
    }

    func testCoreTextLayoutLimitsLinesAndTruncatesLastVisibleLine() throws {
        let text = NSAttributedString(
            string: "one two three four five six seven eight nine ten",
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )
        let fullLayout = try XCTUnwrap(RichCoreTextLayout(
            attributedText: text,
            constrainedWidth: 70
        ))
        let limitedLayout = try XCTUnwrap(RichCoreTextLayout(
            attributedText: text,
            constrainedWidth: 70,
            maximumNumberOfLines: 2,
            lineBreakMode: .byTruncatingTail
        ))

        XCTAssertGreaterThan(fullLayout.lines.count, 2)
        XCTAssertEqual(limitedLayout.lines.count, 2)
        XCTAssertLessThan(
            limitedLayout.size.height,
            fullLayout.size.height,
            "limited=\(limitedLayout.lines.map(\.frame)), full=\(fullLayout.lines.map(\.frame))"
        )
        XCTAssertLessThan(NSMaxRange(try XCTUnwrap(limitedLayout.lines.last).range), text.length)
    }

    @MainActor
    func testSimpleTextAPIUsesSingleElementFastPath() throws {
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 90, height: 100))
        view.font = UIFont.systemFont(ofSize: 16)
        view.textColor = .red
        view.numberOfLines = 1
        view.lineBreakMode = .byTruncatingTail
        view.text = "A simple label-compatible rich view with truncation"

        let layout = try XCTUnwrap(view.currentLayout)
        let runBox = try XCTUnwrap(layout.textRunBoxes.first)
        XCTAssertEqual(view.text, "A simple label-compatible rich view with truncation")
        XCTAssertEqual(runBox.layout.lines.count, 1)
        XCTAssertEqual(view.sizeThatFits(CGSize(width: 90, height: 100)), layout.contentSize)
        XCTAssertEqual(
            runBox.text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
            UIColor.red
        )
    }

    @MainActor
    func testAttributedTextProjectsInlineImageIntoRichImageRun() throws {
        let font = UIFont.systemFont(ofSize: 16)
        let attributedText = NSMutableAttributedString(
            string: "before",
            attributes: [.font: font]
        )
        attributedText.append(RichAttributedInlineImage(
            id: "inline-icon",
            source: RichImageSource(identifier: "inline-icon", image: nil),
            size: CGSize(width: 18, height: 20),
            contentInsets: UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1),
            font: font,
            accessibilityLabel: "图标"
        ).attributedString)
        attributedText.append(NSAttributedString(
            string: "after",
            attributes: [.font: font]
        ))
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))

        view.attributedText = attributedText

        let layout = try XCTUnwrap(view.currentLayout)
        let imageElement = try XCTUnwrap(
            view.currentSnapshot?.root.children.compactMap { $0 as? RichImageElement }.first
        )
        XCTAssertEqual(imageElement.source.identifier, "inline-icon")
        XCTAssertEqual(imageElement.size, CGSize(width: 18, height: 20))
        XCTAssertEqual(layout.textRunBoxes.first?.text.string, "before\u{FFFC}after")
        XCTAssertNotNil(layout.textRunBoxes.first?.layout.inlineRunRect(at: 6))
    }

    private func snapshot(displayRevision: Int) -> RichElementSnapshot {
        let text = RichTextElement(
            id: "text",
            attributedText: NSAttributedString(
                string: "Stable layout",
                attributes: [.font: UIFont.systemFont(ofSize: 16)]
            ),
            revision: RichElementRevision(layout: 0, display: displayRevision)
        )
        return RichElementSnapshot(root: RichContainerElement(id: "root", children: [text]))
    }

    private func textSnapshot(_ attributedText: NSAttributedString) -> RichElementSnapshot {
        RichElementSnapshot(root: RichContainerElement(
            id: "search-root",
            children: [RichTextElement(
                id: "search-text",
                attributedText: attributedText
            )]
        ))
    }

    @MainActor
    private func attachmentRunBox(
        id: String,
        provider: CountingAttachmentProvider
    ) -> RichAttachmentRunBox {
        let element = RichAttachmentElement(
            id: id,
            metrics: RichAttachmentMetrics(size: CGSize(width: 20, height: 20)),
            reuseIdentifier: "media",
            provider: provider
        )
        return RichAttachmentRunBox(
            element: element,
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            contentFrame: CGRect(x: 0, y: 0, width: 20, height: 20)
        )
    }
}

@MainActor
private final class CountingAttachmentProvider: RichAttachmentViewProvider {
    private(set) var makeCount = 0
    private(set) var updateCount = 0

    func makeView() -> UIView {
        makeCount += 1
        return UIView()
    }

    func updateView(_ view: UIView) {
        updateCount += 1
    }
}
