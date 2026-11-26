import CoreText
import UIKit
import XCTest
@testable import RichTextView

final class RichTextLayoutEngineTests: XCTestCase {
    func testDrawingBandsPreservePaintOrderAndDeduplicateSpanningRuns() {
        let size = CGSize(width: 100, height: 4_096)
        let boxes = [(600, 30), (10, 1_800), (3_000, 100), (490, 180)].enumerated().map { index, interval in
            RichRunBox(id: String(index), frame: CGRect(x: 0, y: interval.0, width: 100, height: interval.1))
        }
        let layout = RichTextLayout(rootElementID: "root", constrainedSize: size, contentSize: size, runBoxes: boxes, lines: [])
        let clip = CGRect(x: 0, y: 500, width: 100, height: 220)
        XCTAssertEqual(Array(layout.drawingIndices(in: clip)), [0, 1, 3])
        XCTAssertEqual(Array(layout.drawingIndices(in: clip.offsetBy(dx: 0, dy: 2_400))), [2])
    }

    func testTableCachesOnlyFinalCellWidth() throws {
        let engine = RichTextLayoutEngine.shared
        engine.removeAllCachedLayouts()
        defer { engine.removeAllCachedLayouts() }
        let text = RichTextElement(id: "text", attributedText: NSAttributedString(string: "A"))
        let cell = RichTableCellElement(id: "cell", alignment: .natural, children: [text])
        let row = RichTableRowElement(id: "row", cells: [cell])
        let style = RichTableStyle.standard
        let table = try XCTUnwrap(RichTableLayoutBuilder.make(id: "table", rows: [(row, false)], constrainedWidth: 300, style: style))
        let finalCell = try XCTUnwrap(table.rows.first?.first)
        XCTAssertLessThan(finalCell.frame.width, style.maximumCellContentWidth)
        XCTAssertEqual(engine.cachedLayoutCount, 1)

        let finalLayout = try XCTUnwrap(finalCell.layout.textRunBoxes.first?.layout)
        let repeated = engine.layout(snapshot: finalCell.snapshot, constrainedTo: finalCell.frame.size)
        XCTAssertTrue(repeated.textRunBoxes.first?.layout === finalLayout)
    }

    func testInlineLocalImageIsReleasedWhileEngineIsAlive() {
        let engine = RichTextLayoutEngine()
        let size = CGSize(width: 200, height: 80)
        let prefix = RichTextElement(id: "prefix", attributedText: NSAttributedString(string: "Image "))
        func snapshot(_ children: [RichElement]) -> RichElementSnapshot {
            RichElementSnapshot(root: RichContainerElement(id: "root", children: children))
        }
        _ = engine.layout(snapshot: snapshot([prefix]), constrainedTo: size)
        XCTAssertEqual(engine.cachedLayoutCount, 1)

        weak var weakImage: UIImage?
        weak var weakLayout: RichCoreTextLayout?
        autoreleasepool {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
                context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            weakImage = image
            let element = RichImageElement(id: "image", source: RichImageSource(identifier: "local", image: image),
                                           size: CGSize(width: 16, height: 16), font: .systemFont(ofSize: 16))
            let layout = engine.layout(snapshot: snapshot([prefix, element]), constrainedTo: size)
            weakLayout = layout.textRunBoxes.first?.layout
            XCTAssertEqual(layout.textRunBoxes.first?.text.string, "Image \u{FFFC}")
        }
        XCTAssertNil(weakLayout)
        XCTAssertEqual(engine.cachedLayoutCount, 0)
        // Core Text can keep the last run attributes alive until it lays out another string.
        autoreleasepool {
            _ = RichCoreTextLayout(attributedText: prefix.attributedText, constrainedWidth: size.width)
        }
        XCTAssertNil(weakImage)
    }

    func testInlineAndFittedLatexSkipCache() throws {
        let engine = RichTextLayoutEngine()
        for isBlock in [false, true] {
            let math = try XCTUnwrap(RichLatexLayout(latex: "x", pointSize: 16, isBlock: isBlock, color: .black))
            let latex = RichLatexElement(id: "latex", latex: "x", isBlock: isBlock, layout: math)
            let snapshot = RichElementSnapshot(root: RichContainerElement(id: "root", children: [latex]))
            let layout = engine.layout(snapshot: snapshot, constrainedTo: CGSize(width: 200, height: 80))
            XCTAssertEqual(layout.textRunBoxes.count, 1)
            XCTAssertEqual(engine.cachedLayoutCount, 0)
        }
    }

    func testFlushedInlineRunBoxUsesFirstElementID() {
        let first = RichTextElement(id: "a", attributedText: NSAttributedString(string: "A"))
        let second = RichTextElement(id: "b", attributedText: NSAttributedString(string: "B"))
        let snapshot = RichElementSnapshot(root: RichContainerElement(id: "root", children: [first, second]))
        let layout = RichTextLayoutEngine().layout(snapshot: snapshot, constrainedTo: CGSize(width: 200, height: 80))
        XCTAssertEqual(layout.textRunBoxes.map(\.id), [first.id])
        XCTAssertEqual(layout.textRunBoxes.first?.text.string, "AB")
    }

    func testSlotUpdatesActionAndCopyTextIndependently() throws {
        let engine = RichTextLayoutEngine()
        func run(_ action: String, _ copy: String) throws -> RichTextRunBox {
            let link = RichAnchorElement(id: "link", attributedText: NSAttributedString(string: "Tap"),
                                         actionIdentifier: action, copyText: copy)
            let snapshot = RichElementSnapshot(root: RichContainerElement(id: "root", children: [link]))
            return try XCTUnwrap(engine.layout(snapshot: snapshot, constrainedTo: CGSize(width: 200, height: 80)).textRunBoxes.first)
        }

        let original = try run("first", "Copy A")
        let point = CGPoint(x: 1, y: original.frame.midY)
        XCTAssertEqual(original.actionIdentifier(at: point), "first")
        let changedAction = try run("second", "Copy A")
        XCTAssertEqual(changedAction.actionIdentifier(at: point), "second")
        XCTAssertFalse(original.layout === changedAction.layout)
        let changedCopy = try run("second", "Copy B")
        XCTAssertEqual(changedCopy.segments.first?.copyText, "Copy B")
        XCTAssertFalse(changedAction.layout === changedCopy.layout)
        XCTAssertNil(try run("", "Copy B").actionIdentifier(at: point))
        XCTAssertEqual(engine.cachedLayoutCount, 1)
    }

    func testStreamingSlotsReplacePrefixesAndEvictLeastRecentlyUsedWidth() throws {
        let engine = RichTextLayoutEngine(cacheCapacity: 2)
        func layout(_ length: Int, width: CGFloat) throws -> RichCoreTextLayout {
            let text = RichTextElement(id: "p", attributedText: NSAttributedString(string: String(repeating: "a", count: length)))
            let snapshot = RichElementSnapshot(root: RichContainerElement(id: "root", children: [text]))
            return try XCTUnwrap(engine.layout(snapshot: snapshot, constrainedTo: CGSize(width: width, height: 200)).textRunBoxes.first?.layout)
        }
        for length in 1...100 { _ = try layout(length, width: 80) }
        XCTAssertEqual(engine.cachedLayoutCount, 1)
        let first = try layout(100, width: 80)
        let second = try layout(100, width: 81)
        XCTAssertTrue(try layout(100, width: 80) === first)
        _ = try layout(100, width: 82)
        XCTAssertEqual(engine.cachedLayoutCount, 2)
        XCTAssertFalse(try layout(100, width: 81) === second)
        engine.removeAllCachedLayouts()
        XCTAssertEqual(engine.cachedLayoutCount, 0)
    }

    func testSharedCacheClearsOnBackgroundAndMemoryWarning() {
        let engine = RichTextLayoutEngine.shared
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didReceiveMemoryWarningNotification] {
            _ = engine.layout(snapshot: snapshot(color: .black), constrainedTo: CGSize(width: 200, height: 80))
            XCTAssertGreaterThan(engine.cachedLayoutCount, 0)
            NotificationCenter.default.post(name: name, object: nil)
            XCTAssertEqual(engine.cachedLayoutCount, 0)
        }
    }

    func testSharedCacheSeparatesDocumentsWithIdenticalBlockPaths() throws {
        func layout(_ root: String, text: String) throws -> RichCoreTextLayout {
            let child = RichTextElement(id: "0.0", attributedText: NSAttributedString(string: text))
            let snapshot = RichElementSnapshot(root: RichContainerElement(id: root, children: [child]))
            let result = RichTextLayoutEngine.shared.layout(snapshot: snapshot, constrainedTo: CGSize(width: 200, height: 80))
            return try XCTUnwrap(result.textRunBoxes.first?.layout)
        }
        let first = try layout("doc-a", text: "First")
        let second = try layout("doc-b", text: "Second")
        XCTAssertTrue(try layout("doc-a", text: "First") === first)
        XCTAssertFalse(try layout("doc-a", text: "First extended") === first)
        XCTAssertTrue(try layout("doc-b", text: "Second") === second)
    }

    func testRendererResetReleasesCachedElements() {
        let renderer = RichContentRenderer()
        let document = RichContentDocument(id: "doc", children: [.paragraph(id: "p", text: "Cached")])
        weak var child: RichElement?
        autoreleasepool {
            child = renderer.render(document: document, constrainedWidth: 200, configuration: .standard).snapshot.root.children.first
        }
        XCTAssertNotNil(child)
        renderer.reset()
        XCTAssertNil(child)
    }

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

    func testBlockAttachmentKeepsHeightWhenNestedContentNarrowsItsWidth() async throws {
        let provider = await MainActor.run { CountingAttachmentProvider() }
        let attachment = RichAttachmentElement(
            id: "attachment",
            metrics: RichAttachmentMetrics(size: CGSize(width: 300, height: 120)),
            reuseIdentifier: "attachment",
            provider: provider,
            display: .block
        )
        let nested = RichContainerElement(
            id: "nested",
            children: [attachment],
            contentInsets: RichContainerInsets(top: 0, left: 24, bottom: 0, right: 0)
        )

        let layout = RichTextLayoutEngine().layout(
            snapshot: RichElementSnapshot(root: nested),
            constrainedTo: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        )
        let runBox = try XCTUnwrap(layout.attachmentRunBoxes.first)

        XCTAssertEqual(runBox.frame.size, CGSize(width: 276, height: 120))
        XCTAssertEqual(runBox.contentFrame.size, CGSize(width: 276, height: 120))
    }

    func testColorChangeKeepsGeometry() {
        let engine = RichTextLayoutEngine()
        let first = snapshot(color: .red)
        let second = snapshot(color: .blue)

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
    func testDetachedHostDiscardsAttachmentsOnReuse() {
        let hostView = UIView()
        let manager = RichAttachmentManager(hostView: hostView)
        let provider = CountingAttachmentProvider()
        let owner = UIViewController()
        weak var firstView: UIView?
        autoreleasepool {
            owner.view.addSubview(hostView)
            manager.apply([attachmentRunBox(id: "first", provider: provider)])
            firstView = manager.view(for: "first")
            hostView.removeFromSuperview()
            manager.prepareForReuse()
        }
        XCTAssertNil(firstView)
        manager.apply([attachmentRunBox(id: "second", provider: provider)])

        XCTAssertEqual(provider.makeCount, 2)
        XCTAssertEqual(provider.updateCount, 2)
        XCTAssertEqual(hostView.subviews.count, 1)
        withExtendedLifetime(owner) {}
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

    func testCoreTextLinesAndBadgeReuseOnlyTheCurrentSecondaryThread() throws {
        let layout = try Self.makeThreadIsolationLayout()
        let badge = try XCTUnwrap(layout.attributedText.attribute(
            RichCoreTextAttribute.inlineTextBadge, at: 0, effectiveRange: nil
        ) as? RichInlineTextBadge)

        @Sendable func currentLines() -> [CTLine] {
            let lines = layout.linesForCurrentThread()
            XCTAssertEqual(lines.count, 2)
            let runs = lines.last.flatMap { CTLineGetGlyphRuns($0) as? [CTRun] }
            XCTAssertTrue(runs?.contains { run in
                (CTRunGetAttributes(run) as NSDictionary)[RichCoreTextAttribute.truncationToken] != nil
            } == true)
            return lines + [badge.lineForCurrentThread()]
        }

        // Keep previous instances alive so an allocator cannot recycle their addresses.
        let original = currentLines()
        let finished = expectation(description: "First worker revisited the evicted slot")
        Thread.detachNewThread {
            defer { finished.fulfill() }
            let first = currentLines()
            let firstIDs = first.map(ObjectIdentifier.init)
            XCTAssertTrue(Set(firstIDs).isDisjoint(with: original.map(ObjectIdentifier.init)))
            XCTAssertEqual(firstIDs, currentLines().map(ObjectIdentifier.init))

            let replaced = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                let second = currentLines()
                let secondIDs = second.map(ObjectIdentifier.init)
                XCTAssertTrue(Set(secondIDs).isDisjoint(with: original.map(ObjectIdentifier.init) + firstIDs))
                XCTAssertEqual(secondIDs, currentLines().map(ObjectIdentifier.init))
                replaced.signal()
            }
            XCTAssertEqual(replaced.wait(timeout: .now() + 5), .success)
            withExtendedLifetime(first) {
                XCTAssertTrue(Set(firstIDs).isDisjoint(with: currentLines().map(ObjectIdentifier.init)))
            }
        }
        wait(for: [finished], timeout: 10)
        XCTAssertEqual(original.map(ObjectIdentifier.init), currentLines().map(ObjectIdentifier.init))
    }

    @MainActor
    func testConcurrentDrawingAndMainThreadSelectionProduceStableOutput() async throws {
        let layout = try await Task.detached { try Self.makeThreadIsolationLayout() }.value
        let reference = try XCTUnwrap(Self.renderedPixels(layout))
        XCTAssertTrue(reference.contains { $0 != 0 })
        let range = NSRange(location: 0, length: layout.attributedText.length)
        let rects = layout.selectionRects(for: range)
        XCTAssertEqual(rects.count, 2)
        let points = layout.lines.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
        let positions = try points.map { try XCTUnwrap(layout.closestPosition(to: $0)) }

        let ready = DispatchGroup()
        let start = DispatchSemaphore(value: 0)
        let done = DispatchGroup()
        let workerCount = 4
        for _ in 0..<workerCount {
            ready.enter()
            done.enter()
            DispatchQueue.global().async {
                defer { done.leave() }
                ready.leave()
                start.wait()
                for _ in 0..<64 {
                    autoreleasepool {
                        XCTAssertEqual(Self.renderedPixels(layout), reference)
                    }
                }
            }
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 5), .success)
        for _ in 0..<workerCount { start.signal() }
        for _ in 0..<256 {
            XCTAssertEqual(layout.selectionRects(for: range), rects)
            for (point, position) in zip(points, positions) {
                XCTAssertEqual(layout.closestPosition(to: point), position)
            }
        }
        XCTAssertEqual(done.wait(timeout: .now() + 15), .success)
    }

    private static func makeThreadIsolationLayout() throws -> RichCoreTextLayout {
        let font = UIFont.systemFont(ofSize: 16)
        let badge = RichInlineRunFactory.textBadge(
            attributedText: NSAttributedString(string: "Tag", attributes: [.font: font, .backgroundColor: UIColor.yellow]),
            contentInsets: .zero, outerInsets: .zero, cornerRadius: 2, baselineOffset: 0
        )
        let text = NSMutableAttributedString(attributedString: badge)
        text.append(NSAttributedString(string: " hello\nsecond line with enough words to wrap and truncate",
                                       attributes: [.font: font, .foregroundColor: UIColor.black]))
        return try XCTUnwrap(RichCoreTextLayout(attributedText: text, constrainedWidth: 110,
                                                maximumNumberOfLines: 2, lineBreakMode: .byTruncatingTail))
    }

    private static func renderedPixels(_ layout: RichCoreTextLayout) -> Data? {
        let width = Int(ceil(layout.size.width))
        let height = Int(ceil(layout.size.height))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data else { return nil }
        layout.draw(in: context, canvasHeight: CGFloat(height), origin: .zero, isCancelled: { false })
        return Data(bytes: pixels, count: context.bytesPerRow * height)
    }

    func testCoreTextLayoutSelectsParagraphAcrossWrappedLines() throws {
        let value = "first paragraph wraps across lines\nsecond paragraph"
        let text = NSAttributedString(string: value, attributes: [.font: UIFont.systemFont(ofSize: 16)])
        let layout = try XCTUnwrap(RichCoreTextLayout(attributedText: text, constrainedWidth: 90))
        let wrappedLine = try XCTUnwrap(layout.lines.first { $0.range.location > 0 && $0.range.location < 35 })
        let range = try XCTUnwrap(layout.paragraphRange(at: CGPoint(x: wrappedLine.frame.midX, y: wrappedLine.frame.midY)))

        XCTAssertEqual((value as NSString).substring(with: range), "first paragraph wraps across lines")
    }

    func testListItemSelectionDoesNotIncludeAdjacentItem() throws {
        let marker = RichContainerDecoration.listMarker(
            attributedText: NSAttributedString(string: "•", attributes: [.font: UIFont.systemFont(ofSize: 16)]),
            width: 20
        )
        func item(_ id: String, _ text: String) -> RichContainerElement {
            RichContainerElement(
                id: id,
                children: [RichTextElement(
                    id: "\(id).text",
                    attributedText: NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 16)])
                )],
                contentInsets: RichContainerInsets(left: 20),
                decoration: marker
            )
        }
        let layout = RichTextLayoutEngine().layout(
            snapshot: RichElementSnapshot(root: RichContainerElement(
                id: "root",
                children: [item("first", "first item wraps across lines"), item("second", "second item")]
            )),
            constrainedTo: CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude)
        )
        let first = try XCTUnwrap(layout.textRunBoxes.first)
        let range = try XCTUnwrap(layout.listItemSelectionRange(at: CGPoint(x: first.frame.midX, y: first.frame.midY)))

        XCTAssertEqual(range, first.globalRange)
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

    private func snapshot(color: UIColor) -> RichElementSnapshot {
        let text = RichTextElement(
            id: "text",
            attributedText: NSAttributedString(
                string: "Stable layout",
                attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: color]
            )
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
