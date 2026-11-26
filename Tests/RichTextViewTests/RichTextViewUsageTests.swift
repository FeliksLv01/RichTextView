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

    func testNativeLinkAttributesHitURLAndString() throws {
        let view = makeView()
        let url = try XCTUnwrap(URL(string: "https://example.com/docs"))
        let text = NSMutableAttributedString(string: "URL / String")
        let ranges = [NSRange(location: 0, length: 3), NSRange(location: 6, length: 6)]
        text.addAttribute(.link, value: url, range: ranges[0])
        text.addAttribute(.link, value: url.absoluteString, range: ranges[1])
        text.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: 7, length: 2))
        view.attributedText = text

        let regions = try XCTUnwrap(view.currentLayout?.interactiveRegions)
        XCTAssertEqual(regions.map(\.range), ranges)
        var events: [RichActionEvent] = []
        view.actionEventHandler = { _, event in events.append(event) }
        for region in regions {
            let rect = try XCTUnwrap(region.rects.first)
            let point = CGPoint(x: rect.midX, y: rect.midY)
            XCTAssertEqual(view.action(at: point), RichAction(.link(url)))
            XCTAssertEqual(view.actionIdentifier(at: point), "link:\(url.absoluteString)")
            view.handleContentTap(at: point)
        }
        let outside = CGPoint(x: -1, y: try XCTUnwrap(regions.first?.rects.first).midY)
        XCTAssertNil(view.action(at: outside))
        view.handleContentTap(at: outside)
        XCTAssertEqual(events.map(\.range), ranges)
        XCTAssertEqual(events.map(\.action), Array(repeating: RichAction(.link(url)), count: 2))
    }

    func testTruncatedMiddleDoesNotExposeInvisibleLinks() throws {
        let view = makeView()
        view.frame.size.width = 110
        view.numberOfLines = 1
        view.lineBreakMode = .byTruncatingMiddle
        let source = "First " + String(repeating: "padding ", count: 20) + "hidden " + String(repeating: "padding ", count: 20) + "last"
        let labels = ["First", "hidden", "last"]
        view.setText(source, actions: labels.map { (RichAction(.custom($0)), (source as NSString).range(of: $0)) })
        let regions = try XCTUnwrap(view.currentLayout?.interactiveRegions)
        XCTAssertEqual(regions.map(\.action), [RichAction(.custom("First")), RichAction(.custom("last"))])
        for region in regions {
            let rect = try XCTUnwrap(region.rects.first)
            XCTAssertEqual(view.action(at: CGPoint(x: rect.midX, y: rect.midY)), region.action)
        }
    }

    func testBatchActionsPreserveTextIdentityGeometryAndPayload() throws {
        let view = makeView()
        let source = "👋 hello world"
        let hello = (source as NSString).range(of: "hello")
        let world = (source as NSString).range(of: "world")
        let first = RichAction(.custom("open", payload: ["id": "1"]))
        let second = RichAction(.custom("open", payload: ["id": "2"]))
        view.text = source
        let original = try XCTUnwrap(view.currentLayout?.textRunBoxes.first)
        view.setText(source, actions: [(second, world), (first, hello)])
        let layout = try XCTUnwrap(view.currentLayout)
        let run = try XCTUnwrap(layout.textRunBoxes.first)
        XCTAssertEqual(view.currentSnapshot?.root.children.count, 1)
        XCTAssertEqual(run.segments.map(\.elementID), original.segments.map(\.elementID))
        XCTAssertTrue(run.layout === original.layout)
        XCTAssertEqual(layout.interactiveRegions.map(\.action), [first, second])
        XCTAssertEqual(layout.interactiveRegions.map(\.range), [hello, world])

        var events: [RichActionEvent] = []
        view.actionEventHandler = { _, event in events.append(event) }
        for range in [hello, world] {
            let rects = run.layout.selectionRects(for: range)
            let rect = try XCTUnwrap(rects.first)
            view.handleContentTap(at: CGPoint(x: rect.midX, y: rect.midY))
            let event = try XCTUnwrap(events.last)
            XCTAssertEqual(event.elementID, run.segments.first?.elementID)
            XCTAssertEqual(event.range, range)
            XCTAssertEqual(event.rects, rects)
            XCTAssertEqual(event.trigger, .tap)
        }
        XCTAssertEqual(events.map(\.action), [first, second])
        view.setText(source, actions: [(second, hello), (first, world)])
        XCTAssertFalse(run.text.isEqual(to: try XCTUnwrap(view.currentLayout?.textRunBoxes.first?.text)))
        XCTAssertEqual(view.currentLayout?.interactiveRegions.map(\.action), [second, first])
    }

    func testLegacyIdentifiersRoundTripAndCustomPayloadHasValueEquality() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a:b"))
        let examples: [(RichAction.Kind, String)] = [
            (.link(url), "link:https://example.com/a:b"), (.mention(id: "x:y"), "mention:x:y"),
            (.copyCode(nodeID: "1"), "copy-code:1"), (.codeBlock(nodeID: "2"), "code-block:2"),
            (.custom("custom:foo"), "custom:foo")
        ]
        for (kind, identifier) in examples {
            XCTAssertEqual(RichAction(kind).legacyIdentifier, identifier)
            XCTAssertEqual(RichAction(legacyIdentifier: identifier)?.kind, kind)
        }
        XCTAssertNil(RichAction(legacyIdentifier: ""))
        func attributed(_ id: String) -> NSAttributedString {
            NSAttributedString(string: "Open", attributes: [.richAction: RichAction(.custom("open", payload: ["id": id]))])
        }
        XCTAssertTrue(attributed("1").isEqual(to: attributed("1")))
        XCTAssertFalse(attributed("1").isEqual(to: attributed("2")))
    }

    func testBlockImageAndMentionBadgeProduceTypedRegions() throws {
        let view = makeView()
        let action = RichAction(.custom("preview", payload: ["name": "image"]))
        let image = RichImageElement(id: "photo", source: RichImageSource(identifier: "photo", image: nil),
                                     size: CGSize(width: 16, height: 16), font: view.font, action: action, display: .block)
        let badge = RichTextBadgeElement(id: "badge", attributedText: NSAttributedString(string: "@user"),
                                         contentInsets: .zero, cornerRadius: 0, actionIdentifier: "mention:user")
        view.apply(RichElementSnapshot(root: RichContainerElement(id: "root", children: [image, badge])))
        let regions = try XCTUnwrap(view.currentLayout?.interactiveRegions)
        XCTAssertEqual(regions.map(\.elementID), ["photo", "badge"])
        XCTAssertEqual(regions.map(\.action), [action, RichAction(.mention(id: "user"))])
        XCTAssertEqual(regions.map(\.range), [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)])
        for region in regions {
            let rect = try XCTUnwrap(region.rects.first)
            XCTAssertEqual(view.action(at: CGPoint(x: rect.midX, y: rect.midY)), region.action)
        }
    }

    func testLegacyActionConfigurationAndDelegateForwarding() throws {
        final class Delegate: RichTextViewInteractionDelegate {
            var identifiers: [String] = []
            func richView(_ richView: RichTextView, didActivate actionIdentifier: String) {
                identifiers.append(actionIdentifier)
            }
        }
        let view = makeView()
        let delegate = Delegate()
        view.interactionDelegate = delegate
        view.text = "Link Mention"
        let identifiers = ["link:https://example.com", "mention:abc"]
        view.setTextActions([(identifiers[0], NSRange(location: 0, length: 4))])
        view.setTextAction(identifiers[1], range: NSRange(location: 5, length: 7))
        for region in try XCTUnwrap(view.currentLayout?.interactiveRegions) {
            let rect = try XCTUnwrap(region.rects.first)
            view.handleContentTap(at: CGPoint(x: rect.midX, y: rect.midY))
        }
        XCTAssertEqual(delegate.identifiers, identifiers)
        view.removeAllTextActions()
        XCTAssertEqual(view.currentLayout?.interactiveRegions, [])
    }

    func testNodeActionOverridesLinkAcrossRendererReuse() throws {
        let view = makeView()
        let content = RichLinkContent(href: "https://example.com", title: "Docs", icon: "")
        var events: [RichAction] = []
        view.actionEventHandler = { _, event in events.append(event.action) }
        for id in ["one", "two"] {
            let action = RichAction(.custom("preview", payload: ["id": id]))
            let node = RichContentNode(id: "link", type: .link, content: content, action: action)
            view.setContent(RichContentDocument(id: "doc", children: [node]))
            let region = try XCTUnwrap(view.currentLayout?.interactiveRegions.first)
            let rect = try XCTUnwrap(region.rects.first)
            view.handleContentTap(at: CGPoint(x: rect.midX, y: rect.midY))
            XCTAssertEqual(events.last, action)
        }
        XCTAssertEqual(events.count, 2)
    }

    func testAccessibilityLinksUseUnionFrameAndActivateTheirOwnRegion() throws {
        let view = makeView()
        view.frame.size.width = 85
        let text = "hello a long link spanning multiple lines"
        let action = RichAction(.mention(id: "person"))
        let range = (text as NSString).range(of: "a long link spanning multiple lines")
        view.setAttributedText(NSAttributedString(string: text), actions: [(action, range)])
        let region = try XCTUnwrap(view.currentLayout?.interactiveRegions.first)
        let links = view.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement }.filter {
            $0.accessibilityTraits.contains(.link)
        }
        XCTAssertEqual(links?.count, 1)
        let link = try XCTUnwrap(links?.first)
        XCTAssertGreaterThan(region.rects.count, 1)
        XCTAssertEqual(link.accessibilityLabel, (text as NSString).substring(with: range))
        XCTAssertEqual(link.accessibilityFrameInContainerSpace, region.rects.reduce(.null) { $0.union($1) })
        var event: RichActionEvent?
        view.actionEventHandler = { _, value in event = value }
        XCTAssertTrue(link.accessibilityActivate())
        XCTAssertEqual(event?.trigger, .accessibility)
        XCTAssertEqual(event?.action, action)
        XCTAssertEqual(event?.elementID, region.elementID)
        XCTAssertEqual(event?.range, range)
        XCTAssertEqual(event?.rects, region.rects)
    }

    func testTableCellForwardsActionInHostCoordinates() throws {
        let host = makeView()
        let action = RichAction(.custom("docs", payload: ["id": "v2"]))
        let link = RichContentNode(id: "link", type: .link, content: RichLinkContent(
            href: "https://example.com", title: "Documentation", icon: ""
        ), action: action)
        let cell = RichContentNode(id: "cell", type: .tableCell, content: RichTableCellContent(alignment: .right), children: [link])
        let leading = (0..<6).map { RichContentNode(id: "spacer-\($0)", type: .tableCell) }
        let row = RichContentNode(id: "row", type: .tableRow, children: leading + [cell])
        host.setContent(RichContentDocument(id: "doc", children: [
            .paragraph(id: "intro", text: "Introduction"),
            RichContentNode(id: "table", type: .table, children: [row])
        ]))
        host.layoutIfNeeded()
        let table = try XCTUnwrap(host.subviews.compactMap { $0 as? RichTableView }.first)
        let canvas = try XCTUnwrap(table.canvas)
        let provider = try XCTUnwrap(host.currentLayout?.attachmentRunBoxes.first?.element.provider as? RichTableViewProvider)
        let cellLayout = try XCTUnwrap(provider.model.rows.first?.last)
        let scroll = try XCTUnwrap(canvas.superview as? UIScrollView)
        scroll.contentOffset.x = scroll.contentSize.width - scroll.bounds.width
        XCTAssertGreaterThan(scroll.contentOffset.x, 0)
        let region = try XCTUnwrap(cellLayout.layout.interactiveRegions.first)
        let rect = try XCTUnwrap(region.rects.first)
        var event: RichActionEvent?
        host.actionEventHandler = { sender, value in
            XCTAssertTrue(sender === host)
            event = value
        }
        canvas.handleTap(at: CGPoint(x: cellLayout.frame.minX + rect.midX, y: cellLayout.frame.minY + rect.midY))
        XCTAssertEqual(event?.trigger, .tap)
        XCTAssertEqual(event?.action, action)
        XCTAssertEqual(event?.elementID, link.id)
        XCTAssertEqual(event?.range, region.range)
        XCTAssertNotEqual(event?.rects, region.rects)
        XCTAssertEqual(event?.rects, region.rects.map { canvas.convert($0.offsetBy(dx: cellLayout.frame.minX, dy: cellLayout.frame.minY), to: host) })
        let linkElement = try XCTUnwrap((canvas.accessibilityElements as? [UIAccessibilityElement])?.first { $0.accessibilityTraits.contains(.link) })
        XCTAssertTrue(linkElement.accessibilityActivate())
        XCTAssertEqual(event?.trigger, .accessibility)
    }

    func testTableCopyUsesCellCodeLayout() throws {
        let host = makeView()
        host.codeCopyPasteboard = .withUniqueName()
        defer { UIPasteboard.remove(withName: host.codeCopyPasteboard.name) }
        let code = RichContentNode(id: "snippet", type: .codeBlock, content: RichCodeBlockContent(language: "swift"),
            children: [RichContentNode(id: "source", type: .text, content: RichTextContent(text: "let sample = 42"))])
        let cell = RichContentNode(id: "cell", type: .tableCell, children: [code])
        let row = RichContentNode(id: "row", type: .tableRow, children: [cell])
        host.setContent(RichContentDocument(id: "doc", children: [RichContentNode(id: "table", type: .table, children: [row])]))
        let table = try XCTUnwrap(host.subviews.compactMap { $0 as? RichTableView }.first)
        let canvas = try XCTUnwrap(table.canvas)
        let provider = try XCTUnwrap(host.currentLayout?.attachmentRunBoxes.first?.element.provider as? RichTableViewProvider)
        let source = try XCTUnwrap(provider.model.rows.first?.first)
        let copy = try XCTUnwrap(source.layout.interactiveRegions.first { $0.action.kind == .copyCode(nodeID: "snippet") }?.rects.first)
        canvas.handleTap(at: CGPoint(x: source.frame.minX + copy.midX, y: source.frame.minY + copy.midY))
        XCTAssertEqual(host.codeCopyPasteboard.string, "let sample = 42")
    }

    func testTableCanvasTilesEachAxisAndDrawsFarCells() throws {
        let table = RichTableView()
        for (rowCount, columnCount, tiled) in [(2, 16, false), (2, 17, true), (30, 2, true)] {
            let rows = (0..<rowCount).map { row in
                RichTableRowElement(id: "r\(row)", cells: (0..<columnCount).map { column in
                    let id = "\(row)-\(column)"
                    return RichTableCellElement(id: id, alignment: .left, children: [
                        RichTextElement(id: "text-\(id)", attributedText: NSAttributedString(string: "X"))
                    ])
                })
            }
            let model = try XCTUnwrap(RichTableLayoutBuilder.make(id: "table", rows: rows.map { ($0, false) },
                constrainedWidth: 240, style: RichTableStyle(minimumColumnWidth: 64, maximumColumnWidth: 64)))
            table.apply(model)
            let canvas = try XCTUnwrap(table.canvas)
            XCTAssertEqual(canvas.frame, CGRect(origin: .zero, size: model.contentSize))
            XCTAssertTrue(canvas.subviews.isEmpty)
            XCTAssertEqual(canvas.gestureRecognizers?.count, 1)
            XCTAssertTrue(canvas.gestureRecognizers?.first is UITapGestureRecognizer)
            XCTAssertEqual(canvas.layer is CATiledLayer, tiled)
            if let tile = canvas.layer as? CATiledLayer {
                XCTAssertEqual(tile.tileSize, CGSize(width: 512, height: 512))
                XCTAssertEqual(type(of: tile).fadeDuration(), 0)
            }
            // Clip to the interior of the last cell so neither a grid line nor a header can produce ink.
            let frame = try XCTUnwrap(model.rows.last?.last?.frame)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.preferredRange = .standard
            let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { renderer in
                renderer.cgContext.translateBy(x: -frame.minX, y: -frame.minY)
                canvas.layer.draw(in: renderer.cgContext)
            }
            let bytes = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertTrue(bytes.contains { $0 != 0 })
        }
    }

    private func mountTable(in host: RichTextView) throws -> RichTableView {
        let cell = RichContentNode(id: "cell", type: .tableCell, children: [.paragraph(id: "p", text: "Reusable")])
        let row = RichContentNode(id: "row", type: .tableRow, children: [cell])
        let doc = RichContentDocument(id: "doc", children: [RichContentNode(id: "table", type: .table, children: [row])])
        host.setContent(doc)
        return try XCTUnwrap(host.subviews.compactMap { $0 as? RichTableView }.first)
    }

    func testTableReuseAcrossHostsInSameViewController() throws {
        let owner = UIViewController()
        let first = makeView()
        let second = makeView()
        owner.view.addSubview(first)
        owner.view.addSubview(second)
        let original = try mountTable(in: first)
        first.prepareForReuse()
        XCTAssertNil(original.canvas)
        XCTAssertTrue(try mountTable(in: second) === original)
        XCTAssertNotNil(original.canvas)
    }

    func testTablePoolsFollowNearestViewControllerWhenHostMoves() throws {
        let parent = UIViewController()
        let child = UIViewController()
        parent.addChild(child)
        parent.view.addSubview(child.view)
        child.didMove(toParent: parent)
        let host = makeView()
        parent.view.addSubview(host)
        let original = try mountTable(in: host)
        host.prepareForReuse()
        let childHost = makeView()
        child.view.addSubview(childHost)
        let childTable = try mountTable(in: childHost)
        XCTAssertFalse(childTable === original)
        childHost.prepareForReuse()
        child.view.addSubview(host)
        XCTAssertTrue(try mountTable(in: host) === childTable)
        host.prepareForReuse()
        parent.view.addSubview(host)
        XCTAssertTrue(try mountTable(in: host) === original)
    }

    func testReleasingViewControllerReleasesIdleTable() throws {
        let host = makeView()
        weak var page: UIViewController?
        weak var idleTable: RichTableView?
        try autoreleasepool {
            let owner = UIViewController()
            page = owner
            owner.view.addSubview(host)
            idleTable = try mountTable(in: host)
            host.prepareForReuse()
            XCTAssertNotNil(idleTable)
        }
        XCTAssertNil(page)
        XCTAssertNil(idleTable)
    }

    func testMemoryWarningClearsIdleTablesOnAllPages() throws {
        let firstPage = UIViewController()
        let secondPage = UIViewController()
        let first = makeView()
        let second = makeView()
        firstPage.view.addSubview(first)
        secondPage.view.addSubview(second)
        weak var firstTable: RichTableView?
        weak var secondTable: RichTableView?
        try autoreleasepool {
            firstTable = try mountTable(in: first)
            secondTable = try mountTable(in: second)
            first.prepareForReuse()
            second.prepareForReuse()
        }
        XCTAssertNotNil(firstTable)
        XCTAssertNotNil(secondTable)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(firstTable)
        XCTAssertNil(secondTable)
        withExtendedLifetime((firstPage, secondPage)) {}
    }

    func testHighlightCacheEvictionThemesAndIncrementalStateRelease() throws {
        let highlighter = RichSyntaxHighlighter(maximumCachedCodeBlocks: 2)
        let theme = RichCodeHighlightTheme.monokai
        func highlight(_ code: String, _ id: String = "node", _ style: RichCodeHighlightTheme? = nil) throws -> NSAttributedString {
            try XCTUnwrap(highlighter.highlight(code: code, language: "swift", nodeID: id, theme: style ?? theme))
        }
        let code = "let café = 1"
        let first = try highlight(code)
        XCTAssertTrue(try highlight(code, "other") === first)
        let otherTheme = try highlight(code, "other", .dracula)
        XCTAssertNotEqual(first.attributes(at: 0, effectiveRange: nil) as NSDictionary,
                          otherTheme.attributes(at: 0, effectiveRange: nil) as NSDictionary)
        XCTAssertTrue(try highlight(code) === first)
        _ = try highlight(code + "0")
        XCTAssertTrue(try highlight(code) === first)
        XCTAssertFalse(try highlight(code, "other", .dracula) === otherTheme)
        highlighter.releaseIncrementalState(for: "node")
        let next = try highlight(code + "0\nprint(café)")
        XCTAssertEqual(next.string, code + "0\nprint(café)")
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        highlighter.releaseIncrementalState(for: "node")
        let rebuilt = try highlight(next.string)
        XCTAssertFalse(rebuilt === next)
        XCTAssertEqual(rebuilt, next)
    }

    func testAsyncUpdatesPreserveRenderedContentByDefault() {
        let view = makeView()

        XCTAssertTrue(view.preservesRenderedContentDuringAsyncUpdates)
    }

    func testStreamingReusesUnchangedTilesAndInvalidatesAppearance() throws {
        let view = makeView()
        let layer = try XCTUnwrap(view.layer as? RichRenderLayer)
        let engine = RichTextLayoutEngine()
        func update(_ tail: String) {
            let document = RichContentDocument(id: "stream", children: [
                .paragraph(id: "fixed", text: String(repeating: "Stable paragraph. ", count: 150)),
                .paragraph(id: "tail", text: tail)
            ])
            let snapshot = RichContentRenderer().render(document: document, constrainedWidth: 320, configuration: .standard).snapshot
            let layout = engine.layout(snapshot: snapshot, constrainedTo: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
            view.frame.size = CGSize(width: 320, height: max(1_025, layout.contentSize.height))
            view.apply(snapshot, layout: layout)
            layer.display()
        }
        update("First")
        let tiles = try XCTUnwrap(layer.sublayers?.first as? CATiledLayer)
        let old = DisplaySummary(view.newRenderDisplayTask())
        update("First plus more streamed text")
        XCTAssertTrue(layer.sublayers?.first === tiles)
        let next = view.newRenderDisplayTask()
        let summary = try XCTUnwrap(DisplaySummary(next))
        XCTAssertEqual(summary.unchangedPrefixHeight(comparedTo: old), next.layout?.textRunBoxes.last?.frame.minY)
        next.traits = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(DisplaySummary(next)?.unchangedPrefixHeight(comparedTo: old), 0)
        view.prepareForReuse()
        XCTAssertNil(tiles.superlayer)
    }

    func testStreamingFadeOnlyIncludesAppendedTextAndRejectsRewrites() throws {
        let view = makeView()
        view.text = "Hello"
        let old = view.newRenderDisplayTask()
        view.text = "Hello world"
        let next = view.newRenderDisplayTask()
        old.animatesStreamingChanges = true
        next.animatesStreamingChanges = true
        let summary = try XCTUnwrap(DisplaySummary(next))
        let rects = try XCTUnwrap(summary.appendedTextRects(in: XCTUnwrap(next.layout), comparedTo: DisplaySummary(old)))
        XCTAssertEqual(rects.count, 1)
        let run = try XCTUnwrap(next.layout?.textRunBoxes.first)
        let prefix = try XCTUnwrap(run.layout.selectionRects(for: NSRange(location: 0, length: 5)).first)
        XCTAssertTrue(rects.allSatisfy { $0.minX >= prefix.maxX })
        view.text = "Rewritten answer"
        let rewritten = view.newRenderDisplayTask()
        rewritten.animatesStreamingChanges = true
        XCTAssertNil(DisplaySummary(rewritten)?.appendedTextRects(in: try XCTUnwrap(rewritten.layout), comparedTo: summary))
    }

    func testShortSynchronousLayerDrawsIntoNativeBackingStore() {
        let layer = RichRenderLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 32, height: 24)
        let observer = NativeLayerDelegate()
        layer.delegate = observer
        let delegate = StreamingLayerDelegate()
        layer.richDisplayDelegate = delegate
        var drew = false
        delegate.task.display = { context, size, _ in
            drew = true
            XCTAssertEqual(size, layer.bounds.size)
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
        layer.setNeedsDisplay()
        layer.displayIfNeeded()
        XCTAssertTrue(drew)
        XCTAssertTrue(observer.willDraw)
        XCTAssertNotNil(layer.contents)
    }

    func testAsyncBitmapReplacesContentsOnlyAfterDrawing() async throws {
        let view = makeView()
        view.text = "Old"
        view.layer.display()
        let old = try XCTUnwrap(view.layer.contents as AnyObject?)
        view.preservesRenderedContentDuringAsyncUpdates = false
        view.displaysAsynchronously = true
        let installed = expectation(description: "New bitmap installed")
        view.didDisplay = { installed.fulfill() }
        view.text = "New"
        view.layer.displayIfNeeded()
        XCTAssertTrue(view.layer.contents as AnyObject? === old)
        await fulfillment(of: [installed], timeout: 2)
        XCTAssertNotNil(view.layer.contents)
        XCTAssertFalse(view.layer.contents as AnyObject? === old)
    }

    func testAsyncBitmapKeepsOldGenerationUntilReadyAndDiscardCancelledWork() async throws {
        let layer = RichRenderLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 250)
        let delegate = StreamingLayerDelegate()
        layer.richDisplayDelegate = delegate
        delegate.task.display = { context, size, _ in context.fill(CGRect(origin: .zero, size: size)) }
        layer.display()
        let old = try XCTUnwrap(layer.contents as AnyObject?)
        let started = expectation(description: "Background drawing starts")
        let finished = expectation(description: "Cancelled drawing finishes")
        delegate.task = RichRenderLayerDisplayTask()
        delegate.task.display = { _, _, cancelled in
            if !cancelled() {
                started.fulfill()
                let deadline = CACurrentMediaTime() + 3
                while !cancelled() && CACurrentMediaTime() < deadline { Thread.sleep(forTimeInterval: 0.001) }
                finished.fulfill()
            }
        }
        layer.displaysAsynchronously = true
        layer.setNeedsDisplay()
        layer.display()
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(layer.contents as AnyObject? === old)
        layer.clearDisplayContents()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertNil(layer.contents, "A reused view must reject stale rendering results")
    }

    func testTiledDrawingUsesSystemClipAndDoesNotRetainDisplayTask() throws {
        let layer = RichRenderLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 120, height: 10_000)
        let delegate = StreamingLayerDelegate()
        layer.richDisplayDelegate = delegate
        let clip = CGRect(x: 10, y: 480, width: 50, height: 20)
        var visible: CGRect?
        delegate.task.display = { context, size, _ in
            let rect = context.boundingBoxOfClipPath
            visible = CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height)
        }
        layer.display()
        XCTAssertNil(visible)
        let tiles = try XCTUnwrap(layer.sublayers?.first as? CATiledLayer)
        XCTAssertEqual(tiles.tileSize, CGSize(width: 512, height: 512))
        XCTAssertEqual(type(of: tiles).fadeDuration(), 0)
        _ = UIGraphicsImageRenderer(size: clip.size).image { renderer in
            renderer.cgContext.translateBy(x: -clip.minX, y: -clip.minY)
            tiles.draw(in: renderer.cgContext)
        }
        XCTAssertEqual(visible, clip)

        weak var task: RichRenderLayerDisplayTask?
        task = delegate.task
        delegate.task = RichRenderLayerDisplayTask()
        XCTAssertNil(task)
    }

    func testTilingThresholdUsesBothDimensions() throws {
        let view = makeView()
        view.text = "Threshold"
        let layer = try XCTUnwrap(view.layer as? RichRenderLayer)
        for size in [CGSize(width: 1_025, height: 100), CGSize(width: 100, height: 1_025), CGSize(width: 1_024, height: 100)] {
            layer.bounds.size = size
            layer.display()
            XCTAssertEqual(layer.sublayers?.contains { $0 is CATiledLayer } ?? false, size.width > 1_024 || size.height > 1_024)
        }
        XCTAssertNotNil(layer.contents)
    }

    func testSwitchingContentReleasesDocumentElements() {
        let view = makeView()
        let snapshot = RichElementSnapshot(root: RichContainerElement(id: "replacement", children: []))
        let layout = RichTextLayoutEngine().layout(snapshot: snapshot, constrainedTo: view.bounds.size)
        let replacements: [() -> Void] = [
            { view.text = "Plain" },
            { view.attributedText = NSAttributedString(string: "Attributed") },
            { view.apply(snapshot) },
            { view.apply(snapshot, layout: layout) },
            { view.apply(layout) },
            { view.prepareForReuse() }
        ]
        for replace in replacements {
            weak var child: RichElement?
            autoreleasepool {
                view.setContent(RichContentDocument(id: "doc", children: [.paragraph(id: "p", text: "Prior")]))
                child = view.currentSnapshot?.root.children.first
                XCTAssertNotNil(child)
                replace()
            }
            XCTAssertNil(child)
        }
    }

    func testReuseReleasesTiledLayoutAndPixels() {
        let view = makeView()
        view.bounds.size.height = 4_000
        weak var layout: RichTextLayout?
        autoreleasepool {
            view.text = "Tile"
            view.layer.display()
            layout = view.currentLayout
            XCTAssertNotNil(layout)
            view.prepareForReuse()
            view.layer.display()
        }
        XCTAssertNil(layout)
        XCTAssertNil(view.layer.contents)
        XCTAssertFalse(view.layer.sublayers?.contains { $0 is CATiledLayer } ?? false)
    }

    func testDisplayedBitmapAndSummaryReleaseLayout() throws {
        let layer = RichRenderLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 200, height: 50)
        let delegate = StreamingLayerDelegate()
        layer.richDisplayDelegate = delegate
        weak var previousLayout: RichTextLayout?
        autoreleasepool {
            let view = makeView()
            view.text = "Completed frame"
            delegate.task = view.newRenderDisplayTask()
            delegate.task.animatesStreamingChanges = true
            previousLayout = delegate.task.layout
            layer.display()
            delegate.task = RichRenderLayerDisplayTask()
        }
        XCTAssertNotNil(layer.contents)
        XCTAssertNil(previousLayout)
    }

    func testOffscreenMemoryWarningDiscardsAndRestoresBitmap() {
        let view = makeView()
        view.text = "Restore me"
        view.layer.display()
        XCTAssertNotNil(view.layer.contents)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        view.layer.display()
        XCTAssertNil(view.layer.contents)
        let window = UIWindow(frame: view.bounds)
        window.addSubview(view)
        view.layer.display()
        XCTAssertNotNil(view.layer.contents)
    }

    func testReuseAfterOffscreenMemoryWarningResumesDisplay() {
        let view = makeView()
        view.text = "First cell"
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        view.prepareForReuse()
        view.text = "Reused offscreen"
        view.layer.display()
        XCTAssertNotNil(view.layer.contents)
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

private final class NativeLayerDelegate: NSObject, CALayerDelegate {
    var willDraw = false

    func layerWillDraw(_ layer: CALayer) {
        willDraw = true
    }
}

@MainActor
private final class StreamingLayerDelegate: RichRenderLayerDelegate {
    var task = RichRenderLayerDisplayTask()
    func newRenderDisplayTask(forTiling: Bool) -> RichRenderLayerDisplayTask { task }
}

@MainActor
final class RichSelectionTests: XCTestCase {
    func testStateTransitionsKeepTheOppositeEndpointFixed() {
        let first = RichSemanticPosition(elementID: "p", utf16Offset: 1)
        let middle = RichSemanticPosition(elementID: "p", utf16Offset: 3)
        let last = RichSemanticPosition(elementID: "p", utf16Offset: 5)
        let initial = RichSemanticRange(start: first, end: middle)
        let extended = RichSemanticRange(start: first, end: last)
        var state = RichSelectionState.idle
        state.beginDrag(.start)
        XCTAssertEqual(state, .idle)
        state = .longPressing(anchor: initial, current: initial)
        state.extend(to: extended)
        XCTAssertEqual(state, .longPressing(anchor: initial, current: extended))
        state.finish()
        XCTAssertEqual(state, .selected(extended))
        state.beginDrag(.end)
        state.extend(to: initial)
        XCTAssertEqual(state, .dragging(handle: .end, anchor: first, current: initial))
        state.finish()
        state.beginDrag(.start)
        XCTAssertEqual(state, .dragging(handle: .start, anchor: middle, current: initial))
    }

    func testStreamingRebasesLongPressAndHandleAnchors() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let view = RichTextView(frame: window.bounds)
        window.addSubview(view)
        view.initialSelectionPolicy = .paragraph

        func update(prefix: String, includeAnchor: Bool = true) {
            var blocks = [("prefix", prefix)]
            if includeAnchor { blocks.append(("anchor", "Alpha")) }
            blocks.append(("tail", "Bravo"))
            let children = blocks.map { id, text in
                RichTextElement(id: id, attributedText: NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 20)]),
                                display: .block)
            }
            let snapshot = RichElementSnapshot(root: RichContainerElement(id: "stream", children: children, spacing: 12))
            view.apply(snapshot, layout: RichTextLayoutEngine.shared.layout(snapshot: snapshot, constrainedTo: view.bounds.size))
        }
        func box(_ id: String) throws -> RichTextRunBox {
            try XCTUnwrap(view.currentLayout?.textRunBoxes.first { $0.segments.first?.elementID == id })
        }
        func point(_ id: String, atEnd: Bool = false) throws -> CGPoint {
            let frame = try box(id).frame
            return CGPoint(x: atEnd ? frame.maxX : frame.midX, y: frame.midY)
        }

        update(prefix: "1")
        let controller = try enableSelection(in: view)
        controller.beginLongPress(at: try point("anchor"))
        let initial = try XCTUnwrap(view.currentSelection?.semanticRange)
        XCTAssertEqual(initial.start.elementID, "anchor")
        controller.extendSelection(to: try point("tail", atEnd: true))
        let extended = try XCTUnwrap(view.currentSelection?.semanticRange)
        XCTAssertEqual(extended.end.elementID, "tail")
        update(prefix: "A longer prefix")
        XCTAssertEqual(controller.state, .longPressing(anchor: initial, current: extended))
        XCTAssertEqual(view.currentSelection?.globalRange.location, try box("anchor").globalRange.location)
        controller.extendSelection(to: try point("anchor"))
        XCTAssertEqual(view.currentSelection?.semanticRange, initial)
        controller.finishInteraction()
        controller.beginHandleDrag(.end, at: try point("anchor", atEnd: true))
        update(prefix: "A much longer prefix, inserted while dragging")
        controller.extendSelection(to: try point("tail", atEnd: true))
        XCTAssertEqual(controller.state, .dragging(handle: .end, anchor: initial.start, current: extended))
        XCTAssertEqual(view.currentSelection?.plainText, "Alpha\nBravo")
        controller.finishInteraction()
        update(prefix: "Short again")
        XCTAssertEqual(controller.state, .selected(extended))
        XCTAssertEqual(view.currentSelection?.globalRange.location, try box("anchor").globalRange.location)
        update(prefix: "Gone", includeAnchor: false)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(view.currentSelection)
    }

    func testLosingGestureAnchorClearsAnOtherwiseMappableRange() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let view = RichTextView(frame: window.bounds)
        window.addSubview(view)
        view.initialSelectionPolicy = .currentLine
        let controller = try enableSelection(in: view)
        func update(includeMiddle: Bool) {
            let ids = includeMiddle ? ["first", "middle", "tail"] : ["first", "tail"]
            let children = ids.map { id in
                RichTextElement(id: id, attributedText: NSAttributedString(string: id, attributes: [.font: UIFont.systemFont(ofSize: 20)]),
                                display: id == "tail" ? .block : .inline)
            }
            let snapshot = RichElementSnapshot(root: RichContainerElement(id: "stream", children: children))
            view.apply(snapshot, layout: RichTextLayoutEngine.shared.layout(snapshot: snapshot, constrainedTo: view.bounds.size))
        }
        for dragHandle in [false, true] {
            update(includeMiddle: true)
            let first = try XCTUnwrap(view.currentLayout?.textRunBoxes.first)
            let last = try XCTUnwrap(view.currentLayout?.textRunBoxes.last)
            let start = CGPoint(x: first.frame.midX, y: first.frame.midY)
            controller.beginLongPress(at: start)
            XCTAssertEqual(view.currentSelection?.semanticRange.end.elementID, "middle")
            if dragHandle {
                controller.finishInteraction()
                controller.beginHandleDrag(.start, at: start)
            }
            controller.extendSelection(to: CGPoint(x: last.frame.maxX, y: last.frame.midY))
            let current = try XCTUnwrap(controller.state.current)
            XCTAssertEqual(current.start.elementID, dragHandle ? "tail" : "first")
            XCTAssertEqual(current.end.elementID, "tail")
            update(includeMiddle: false)
            XCTAssertEqual(controller.state, .idle)
            XCTAssertNil(view.currentSelection)
            XCTAssertFalse(window.subviews.contains { $0 is RichSelectionHandleOverlay })
        }
    }

    func testWindowSelectionOwnershipAndTeardown() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        let a = RichTextView(frame: window.bounds)
        let b = RichTextView(frame: window.bounds)
        window.addSubview(a)
        window.addSubview(b)
        a.text = "Cell A"
        b.text = "Cell B"
        let first = try enableSelection(in: a)
        let second = try enableSelection(in: b)
        first.beginLongPress(at: CGPoint(x: 5, y: 5))
        let oldOverlay = try XCTUnwrap(window.subviews.first { $0 is RichSelectionHandleOverlay })
        XCTAssertNotNil(a.currentSelection)
        second.beginLongPress(at: CGPoint(x: 5, y: 5))
        XCTAssertNil(a.currentSelection)
        XCTAssertNil(oldOverlay.superview)
        XCTAssertEqual(window.subviews.filter { $0 is RichSelectionHandleOverlay }.count, 1)
        XCTAssertEqual(b.currentSelection?.plainText, "Cell B")
        let otherWindow = UIWindow(frame: window.bounds)
        otherWindow.addSubview(a)
        first.beginLongPress(at: CGPoint(x: 5, y: 5))
        XCTAssertNotNil(a.currentSelection)
        XCTAssertNotNil(b.currentSelection)
        window.addSubview(a)
        XCTAssertNil(a.currentSelection)
        XCTAssertFalse(otherWindow.subviews.contains { $0 is RichSelectionHandleOverlay })
        XCTAssertNotNil(b.currentSelection)
        b.removeFromSuperview()
        XCTAssertNil(b.currentSelection)
        XCTAssertFalse(window.subviews.contains { $0 is RichSelectionHandleOverlay })
        XCTAssertFalse(b.subviews.contains { $0 is RichSelectionHighlightView })
        window.addSubview(b)
        second.beginLongPress(at: CGPoint(x: 5, y: 5))
        b.prepareForReuse()
        XCTAssertNil(b.currentSelection)
        XCTAssertFalse(window.subviews.contains { $0 is RichSelectionHandleOverlay })
    }

    func testViewportRecyclesBitmapsAndKeepsActiveSelection() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 512))
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 12288))
        window.addSubview(view)
        view.text = String(repeating: "Document line\n", count: 800)
        view.initialSelectionPolicy = .currentLine
        let controller = try enableSelection(in: view)
        controller.beginLongPress(at: CGPoint(x: 5, y: 5))
        controller.finishInteraction()
        let selected = try XCTUnwrap(view.currentSelection)
        let highlight = try XCTUnwrap(view.subviews.first { $0 is RichSelectionHighlightView })
        let handles = try XCTUnwrap(window.subviews.first { $0 is RichSelectionHandleOverlay })
        let firstScreen = window.bounds
        func update(_ rect: CGRect?) {
            view.updateVisibleRect(rect)
            view.layer.displayIfNeeded()
        }
        func strips() -> [CALayer] {
            (view.layer.sublayers ?? []).filter { $0 !== highlight.layer && $0.contents != nil }
        }
        update(firstScreen)
        let first = strips()
        XCTAssertEqual(first.count, 2)
        let top = try XCTUnwrap(first.first { $0.frame.minY == 0 })
        let bitmap = try XCTUnwrap(top.contents as AnyObject?)
        update(firstScreen.offsetBy(dx: 0, dy: 768))
        XCTAssertTrue(top.contents as AnyObject? === bitmap, "Retain strips within one screen of the viewport")
        XCTAssertEqual(Set(strips().map { $0.frame.minY }), [0, 512, 1024])
        update(.zero)
        XCTAssertTrue(top.contents as AnyObject? === bitmap)
        update(firstScreen.offsetBy(dx: 0, dy: 1280))
        XCTAssertFalse(top.contents as AnyObject? === bitmap, "Release strips beyond the one-screen buffer")
        update(firstScreen.offsetBy(dx: 0, dy: 8192))
        XCTAssertTrue(strips().allSatisfy { $0.frame.minY >= 7680 })
        XCTAssertTrue(strips().contains { strip in first.contains { $0 === strip } })
        XCTAssertFalse(top.contents as AnyObject? === bitmap)
        let far = strips()
        update(firstScreen)
        let retired = far.filter { $0.superlayer == nil }
        XCTAssertFalse(retired.isEmpty)
        XCTAssertTrue(retired.allSatisfy { $0.contents == nil })
        let restored = try XCTUnwrap(strips().first { $0.frame.minY == 0 })
        let contents = try XCTUnwrap(restored.contents)
        XCTAssertEqual(CFGetTypeID(contents as CFTypeRef), CGImage.typeID)
        let redrawn = contents as! CGImage
        let data = try XCTUnwrap(redrawn.dataProvider?.data) as Data
        XCTAssertTrue(data.contains { $0 != 0 })
        XCTAssertEqual(view.currentSelection?.semanticRange, selected.semanticRange)
        XCTAssertTrue(highlight.superview === view)
        XCTAssertTrue(handles.superview === window)
        controller.beginHandleDrag(.end, at: CGPoint(x: 10, y: 8))
        controller.extendSelection(to: CGPoint(x: 60, y: 80))
        XCTAssertGreaterThan(view.currentSelection?.globalRange.length ?? 0, selected.globalRange.length)
        update(nil)
        XCTAssertTrue(view.layer.sublayers?.contains { $0 is CATiledLayer } == true)
    }

    func testDisabledSelectionInstallsOnlyContentTap() throws {
        let view = RichTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let window = UIWindow(frame: view.bounds)
        window.addSubview(view)
        view.text = "Tap"
        view.clearTextSelection()
        XCTAssertFalse(view.isTextSelectionEnabled)
        XCTAssertEqual(view.gestureRecognizers?.count, 1)
        XCTAssertTrue(view.gestureRecognizers?.first is UITapGestureRecognizer)
        XCTAssertFalse(view.subviews.contains { $0 is RichSelectionHighlightView })
        XCTAssertFalse(window.subviews.contains { $0 is RichSelectionHandleOverlay })
        view.prioritizeSelection(over: UILongPressGestureRecognizer())
        let press = try XCTUnwrap(view.gestureRecognizers?.first { $0 is UILongPressGestureRecognizer })
        XCTAssertFalse(press.isEnabled)
        view.isTextSelectionEnabled = true
        XCTAssertTrue(press.isEnabled)
        view.text = ""
        XCTAssertEqual(press.delegate?.gestureRecognizerShouldBegin?(press), false)
    }

    func testHandlesPassThroughClipAndTrackVerticalScroll() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let list = UIScrollView(frame: CGRect(x: 0, y: 70, width: 320, height: 240))
        let carousel = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        list.contentSize = CGSize(width: 320, height: 800)
        carousel.contentSize = CGSize(width: 900, height: 240)
        list.canCancelContentTouches = true
        carousel.canCancelContentTouches = false
        window.addSubview(list)
        list.addSubview(carousel)
        let view = RichTextView(frame: CGRect(x: 50, y: 70, width: 180, height: 40))
        view.clipsToBounds = true
        carousel.addSubview(view)
        view.text = "Selectable text"
        let controller = try enableSelection(in: view)
        controller.beginLongPress(at: CGPoint(x: 5, y: 5))
        controller.finishInteraction()
        let overlay = try XCTUnwrap(window.subviews.first { $0 is RichSelectionHandleOverlay } as? RichSelectionHandleOverlay)
        let handle = try XCTUnwrap(overlay.subviews.compactMap { $0 as? RichSelectionHandleView }.first { $0.kind == .start })
        XCTAssertTrue(list.canCancelContentTouches)
        XCTAssertFalse(carousel.canCancelContentTouches)
        XCTAssertTrue(overlay.clipsToBounds)
        XCTAssertEqual(overlay.frame, list.frame)
        XCTAssertEqual(overlay.subviews.count, 2)
        XCTAssertTrue(overlay.subviews.allSatisfy { ($0.gestureRecognizers?.first as? UIPanGestureRecognizer)?.maximumNumberOfTouches == 1 })
        let outsideHost = view.convert(CGPoint(x: -8, y: -8), to: window)
        XCTAssertTrue(view.isSelectionHandleTouch(atWindowPoint: outsideHost))
        XCTAssertTrue(overlay.hitTest(overlay.convert(outsideHost, from: window), with: nil) === handle)
        XCTAssertNil(overlay.hitTest(CGPoint(x: 300, y: 200), with: nil))
        let oldY = handle.frame.midY
        list.contentOffset.y = 30
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { abs(handle.frame.midY - (oldY - 30)) < 0.01 }
        }, object: nil)
        await fulfillment(of: [moved], timeout: 3)
        XCTAssertEqual(overlay.frame, list.frame)
        XCTAssertFalse(view.isSelectionHandleTouch(atWindowPoint: CGPoint(x: outsideHost.x, y: list.frame.minY - 1)))
        view.clearTextSelection()
        XCTAssertNil(overlay.superview)
        XCTAssertTrue(list.canCancelContentTouches)
        XCTAssertFalse(carousel.canCancelContentTouches)
    }

    private func enableSelection(in view: RichTextView) throws -> RichSelectionController {
        view.isTextSelectionEnabled = true
        let press = try XCTUnwrap(view.gestureRecognizers?.first { $0 is UILongPressGestureRecognizer })
        return try XCTUnwrap(press.delegate as? RichSelectionController)
    }
}
