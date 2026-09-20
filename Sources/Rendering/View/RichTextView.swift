import UIKit

@MainActor
public final class RichTextView: UIView, RichRenderLayerDelegate {
    private struct SimpleTextAction {
        let identifier: String
        let range: NSRange
    }

    private enum SimpleContent {
        case text(String)
        case attributedText(NSAttributedString)
    }

    private struct DocumentContent {
        let document: RichContentDocument
        let configuration: RichContentRenderingConfiguration
        let resolver: (any RichContentPresentationResolving)?
    }

    public override class var layerClass: AnyClass { RichRenderLayer.self }

    public var text: String? {
        get {
            switch simpleContent {
            case let .text(text): text
            case let .attributedText(text): text.string
            case nil: nil
            }
        }
        set {
            simpleTextActions.removeAll()
            simpleTextActionHandlers.removeAll()
            documentContent = nil
            simpleContent = newValue.map(SimpleContent.text)
            updateSimpleContent()
        }
    }

    public var attributedText: NSAttributedString? {
        get {
            switch simpleContent {
            case let .text(text): makeSimpleAttributedText(from: text)
            case let .attributedText(text): text
            case nil: nil
            }
        }
        set {
            simpleTextActions.removeAll()
            simpleTextActionHandlers.removeAll()
            documentContent = nil
            simpleContent = newValue.map {
                SimpleContent.attributedText(NSAttributedString(attributedString: $0))
            }
            updateSimpleContent()
        }
    }

    public var font = UIFont.systemFont(ofSize: UIFont.systemFontSize) {
        didSet { updateSimpleContentIfNeeded() }
    }

    public var textColor = UIColor.label {
        didSet { updateSimpleContentIfNeeded() }
    }

    public var textAlignment: NSTextAlignment = .natural {
        didSet { updateSimpleContentIfNeeded() }
    }

    public var lineBreakMode: NSLineBreakMode = .byWordWrapping {
        didSet { updateSimpleContentIfNeeded() }
    }

    public var numberOfLines = 0 {
        didSet {
            if numberOfLines < 0 { numberOfLines = 0 }
            updateSimpleContentIfNeeded()
        }
    }

    public var isTextSelectionEnabled = false {
        didSet {
            selectionController.isEnabled = isTextSelectionEnabled
            if !isTextSelectionEnabled { selectionController.clearSelection() }
        }
    }
    public var initialSelectionPolicy: RichInitialSelectionPolicy = .allContent

    public weak var interactionDelegate: RichTextViewInteractionDelegate?
    public var actionHandler: ((RichTextView, String) -> Void)?
    public var selectionHandler: ((RichSelection?) -> Void)?
    public var selectionMenuActions: ((RichSelection) -> [RichSelectionMenuAction])?
    public weak var selectionMenuPresenter: RichSelectionMenuPresenting?
    public let imageLoader: RichImageLoader?
    public var displaysAsynchronously: Bool {
        get { renderLayer.displaysAsynchronously }
        set { renderLayer.displaysAsynchronously = newValue }
    }
    public var laysOutAsynchronously = true
    /// Fade only newly appended text. Existing content, layout and selection stay unchanged.
    public var animatesStreamingChanges = false

    public var preservesRenderedContentDuringAsyncUpdates = true

    public private(set) var currentLayout: RichTextLayout?
    public private(set) var currentSnapshot: RichElementSnapshot?
    public private(set) var currentSelection: RichSelection?

    private let layoutEngine: RichTextLayoutEngine
    private lazy var attachmentManager = RichAttachmentManager(hostView: self)
    private lazy var selectionController = RichSelectionController(hostView: self)
    private var layoutTask: Task<Void, Never>?
    private var generation: UInt = 0
    private var simpleContent: SimpleContent?
    private var documentContent: DocumentContent?
    private var simpleTextActions: [SimpleTextAction] = []
    private var simpleTextActionHandlers: [String: (RichTextView) -> Void] = [:]
    private var lastLayoutWidth: CGFloat = 0
    private var usesPrecomputedLayout = false
    private var loadedImages: [String: UIImage] = [:]
    private var imageLoadTasks: [String: RichImageLoadTask] = [:]
    private var remoteImageIdentifiers = Set<String>()
    private weak var activeSelectionTouch: UITouch?
    private var selectionTouchStartPoint: CGPoint?
    private var didMoveSelectionTouch = false

    // swiftlint:disable:next force_cast
    private var renderLayer: RichRenderLayer { layer as! RichRenderLayer }

    public init(
        frame: CGRect = .zero,
        layoutEngine: RichTextLayoutEngine = RichTextLayoutEngine(),
        imageLoader: RichImageLoader? = nil
    ) {
        self.layoutEngine = layoutEngine
        self.imageLoader = imageLoader
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        layoutTask?.cancel()
    }

    public func apply(_ snapshot: RichElementSnapshot) {
        documentContent = nil
        simpleContent = nil
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        usesPrecomputedLayout = false
        scheduleLayout(for: snapshot)
    }

    public func setContent(
        _ document: RichContentDocument,
        configuration: RichContentRenderingConfiguration = .standard,
        resolver: (any RichContentPresentationResolving)? = nil
    ) {
        simpleContent = nil
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        usesPrecomputedLayout = false
        documentContent = DocumentContent(
            document: document,
            configuration: configuration,
            resolver: resolver
        )
        updateDocumentContent()
    }

    public func setTextAction(_ actionIdentifier: String, range: NSRange) {
        guard let simpleContent else { return }
        let textLength: Int
        switch simpleContent {
        case let .text(text): textLength = text.utf16.count
        case let .attributedText(text): textLength = text.length
        }
        guard !actionIdentifier.isEmpty,
              range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= textLength else { return }
        removeTextActions(intersecting: range)
        simpleTextActions.append(SimpleTextAction(identifier: actionIdentifier, range: range))
        simpleTextActions.sort { $0.range.location < $1.range.location }
        updateSimpleContent()
    }

    public func setTextAction(
        range: NSRange,
        handler: @escaping (RichTextView) -> Void
    ) {
        let identifier = "simple-range-\(range.location)-\(range.length)"
        setTextAction(identifier, range: range)
        guard simpleTextActions.contains(where: { $0.identifier == identifier }) else {
            return
        }
        simpleTextActionHandlers[identifier] = handler
    }

    public func setTextActions(_ actions: [(identifier: String, range: NSRange)]) {
        guard let simpleContent else { return }
        let textLength: Int
        switch simpleContent {
        case let .text(text): textLength = text.utf16.count
        case let .attributedText(text): textLength = text.length
        }
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        for action in actions.sorted(by: { $0.range.location < $1.range.location }) {
            guard !action.identifier.isEmpty,
                  action.range.location >= 0,
                  action.range.length > 0,
                  NSMaxRange(action.range) <= textLength,
                  !simpleTextActions.contains(where: {
                      NSIntersectionRange($0.range, action.range).length > 0
                  }) else { continue }
            simpleTextActions.append(SimpleTextAction(
                identifier: action.identifier,
                range: action.range
            ))
        }
        updateSimpleContent()
    }

    public func removeAllTextActions() {
        guard !simpleTextActions.isEmpty else { return }
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        updateSimpleContent()
    }

    public func actionIdentifier(at point: CGPoint) -> String? {
        guard let layout = currentLayout else { return nil }
        for runBox in layout.runBoxes.reversed() {
            guard let textRunBox = runBox as? RichTextRunBox,
                  textRunBox.frame.contains(point) else { continue }
            let localPoint = CGPoint(
                x: point.x - textRunBox.frame.minX,
                y: point.y - textRunBox.frame.minY
            )
            return textRunBox.actionIdentifier(at: localPoint)
        }
        return nil
    }

    private func scheduleLayout(for snapshot: RichElementSnapshot) {
        currentSnapshot = snapshot
        generation &+= 1
        let requestedGeneration = generation
        let constrainedSize = bounds.size
        layoutTask?.cancel()
        guard laysOutAsynchronously else {
            apply(layoutEngine.layout(snapshot: snapshot, constrainedTo: constrainedSize))
            return
        }
        layoutTask = Task { [weak self, layoutEngine] in
            let layout = await Task.detached(priority: .userInitiated) {
                layoutEngine.layout(snapshot: snapshot, constrainedTo: constrainedSize)
            }.value
            guard !Task.isCancelled else { return }
            guard let self, self.generation == requestedGeneration else { return }
            self.apply(layout)
        }
    }

    public func apply(_ updates: [RichElementUpdate]) {
        guard let currentSnapshot else { return }
        apply(currentSnapshot.applying(updates))
    }

    public func apply(_ snapshot: RichElementSnapshot, layout: RichTextLayout) {
        precondition(snapshot.root.id == layout.rootElementID, "Snapshot and layout must have the same root ID")
        documentContent = nil
        simpleContent = nil
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        currentSnapshot = snapshot
        usesPrecomputedLayout = true
        apply(layout)
    }

    public func apply(_ layout: RichTextLayout) {
        generation &+= 1
        layoutTask?.cancel()
        if displaysAsynchronously && !preservesRenderedContentDuringAsyncUpdates {
            renderLayer.clearDisplayContents()
        }
        currentLayout = layout
        lastLayoutWidth = layout.constrainedSize.width
        attachmentManager.apply(layout.attachmentRunBoxes)
        synchronizeImageLoads()
        selectionController.apply(layout: layout)
        updateAccessibility(using: layout)
        renderLayer.setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    public func prepareForReuse() {
        finishSelectionTouchRouting()
        generation &+= 1
        layoutTask?.cancel()
        layoutTask = nil
        currentSnapshot = nil
        currentLayout = nil
        documentContent = nil
        simpleContent = nil
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        lastLayoutWidth = 0
        usesPrecomputedLayout = false
        attachmentManager.prepareForReuse()
        cancelImageLoads()
        loadedImages.removeAll()
        remoteImageIdentifiers.removeAll()
        selectionController.clearSelection()
        selectionMenuPresenter?.dismissCopyMenu(from: self)
        accessibilityElements = nil
        renderLayer.clearDisplayContents()
    }

    public func clearTextSelection() {
        selectionController.clearSelection()
    }

    public func isSelectionHandleTouch(atWindowPoint windowPoint: CGPoint) -> Bool {
        guard let window else { return false }
        return selectionController.isTouchingSelectionHandle(at: convert(windowPoint, from: window))
    }

    public func prioritizeSelection(over competingGestureRecognizer: UIGestureRecognizer) {
        competingGestureRecognizer.require(toFail: selectionController.selectionLongPressGestureRecognizer)
    }

    public override var intrinsicContentSize: CGSize {
        currentLayout?.contentSize ?? .zero
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = min(100_000, max(0, size.width))
        guard width > 0 else { return .zero }
        let snapshot = simpleContent.map(makeSimpleSnapshot)
            ?? documentContent.map { makeDocumentSnapshot($0, constrainedWidth: width) }
            ?? currentSnapshot
        guard let snapshot else { return .zero }
        return layoutEngine.layout(
            snapshot: snapshot,
            constrainedTo: CGSize(width: width, height: size.height)
        ).contentSize
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !usesPrecomputedLayout,
              bounds.width > 0,
              abs(bounds.width - lastLayoutWidth) > 0.5 else { return }
        if simpleContent != nil {
            updateSimpleContent()
        } else if documentContent != nil {
            updateDocumentContent()
        } else if let currentSnapshot {
            scheduleLayout(for: currentSnapshot)
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled,
              !isHidden,
              alpha > 0.01,
              self.point(inside: point, with: event) else { return nil }
        if selectionController.shouldRouteHandleTouch(at: point) {
            return self
        }
        return super.hitTest(point, with: event)
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event)
            || selectionController.shouldRouteHandleTouch(at: point)
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeSelectionTouch == nil,
              touches.count == 1,
              let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }
        let point = touch.location(in: self)
        guard selectionController.beginHandleDrag(at: point) else {
            super.touchesBegan(touches, with: event)
            return
        }
        activeSelectionTouch = touch
        selectionTouchStartPoint = point
        didMoveSelectionTouch = false
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeSelectionTouch,
              touches.contains(where: { $0 === activeSelectionTouch }) else {
            super.touchesMoved(touches, with: event)
            return
        }
        let point = activeSelectionTouch.location(in: self)
        if let startPoint = selectionTouchStartPoint,
           hypot(point.x - startPoint.x, point.y - startPoint.y) >= 1 {
            didMoveSelectionTouch = true
        }
        guard didMoveSelectionTouch else { return }
        selectionController.moveHandleDrag(to: point, finished: false)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeSelectionTouch,
              touches.contains(where: { $0 === activeSelectionTouch }) else {
            super.touchesEnded(touches, with: event)
            return
        }
        selectionController.endHandleDrag(
            at: activeSelectionTouch.location(in: self),
            shouldUpdate: didMoveSelectionTouch
        )
        finishSelectionTouchRouting()
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeSelectionTouch,
              touches.contains(where: { $0 === activeSelectionTouch }) else {
            super.touchesCancelled(touches, with: event)
            return
        }
        selectionController.cancelHandleDrag()
        finishSelectionTouchRouting()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
        renderLayer.setNeedsDisplay()
        selectionController.updateAppearance()
    }

    func newRenderDisplayTask() -> RichRenderLayerDisplayTask {
        let task = RichRenderLayerDisplayTask()
        let layout = currentLayout
        let loadedImages = loadedImages
        let displayTraits = traitCollection
        task.animatesStreamingChanges = animatesStreamingChanges && window != nil && !UIAccessibility.isReduceMotionEnabled
        task.layout = layout
        task.traits = displayTraits
        task.images = loadedImages
        task.display = { context, size, isCancelled in
            displayTraits.performAsCurrent {
                guard let layout else { return }
                let clip = context.boundingBoxOfClipPath
                let visible = CGRect(x: clip.minX, y: size.height - clip.maxY, width: clip.width, height: clip.height)
                for runBox in layout.runBoxes where runBox.frame.intersects(visible) {
                    guard let decorationRunBox = runBox as? RichDecorationRunBox,
                          case let .background(color, cornerRadius) = decorationRunBox.decoration else { continue }
                    let rect = CGRect(
                        x: decorationRunBox.frame.minX,
                        y: size.height - decorationRunBox.frame.maxY,
                        width: decorationRunBox.frame.width,
                        height: decorationRunBox.frame.height
                    )
                    context.setFillColor(color.cgColor)
                    context.addPath(CGPath(
                        roundedRect: rect,
                        cornerWidth: cornerRadius,
                        cornerHeight: cornerRadius,
                        transform: nil
                    ))
                    context.fillPath()
                }
                for runBox in layout.runBoxes where runBox.frame.intersects(visible) {
                    if isCancelled() { return }
                    if let textRunBox = runBox as? RichTextRunBox {
                        textRunBox.layout.draw(
                            in: context,
                            canvasHeight: size.height,
                            origin: textRunBox.frame.origin,
                            imageResolver: { loadedImages[$0] },
                            isCancelled: isCancelled
                        )
                    } else if let imageRunBox = runBox as? RichImageRunBox,
                              let image = (loadedImages[imageRunBox.element.source.identifier]
                                  ?? imageRunBox.element.source.image)?.cgImage {
                        let imageFrame = CGRect(
                            x: imageRunBox.frame.minX,
                            y: size.height - imageRunBox.frame.maxY,
                            width: imageRunBox.frame.width,
                            height: imageRunBox.frame.height
                        )
                        RichImageDrawing.draw(
                            image,
                            in: RichImageDrawing.fittedRect(
                                imageSize: CGSize(width: image.width, height: image.height),
                                in: imageFrame,
                                contentInsets: imageRunBox.element.contentInsets,
                                contentMode: imageRunBox.element.contentMode
                            ),
                            tintColor: imageRunBox.element.tintColor,
                            context: context
                        )
                    } else if let decorationRunBox = runBox as? RichDecorationRunBox {
                        switch decorationRunBox.decoration {
                        case .background:
                            continue
                        case let .leadingRule(color, _):
                            context.setFillColor(color.cgColor)
                            context.fill(CGRect(
                                x: decorationRunBox.frame.minX,
                                y: size.height - decorationRunBox.frame.maxY,
                                width: decorationRunBox.frame.width,
                                height: decorationRunBox.frame.height
                            ))
                        case .listMarker:
                            decorationRunBox.textLayout?.draw(
                                in: context,
                                canvasHeight: size.height,
                                origin: decorationRunBox.frame.origin,
                                imageResolver: { loadedImages[$0] },
                                isCancelled: isCancelled
                            )
                        case let .horizontalRule(color):
                            context.setFillColor(color.cgColor)
                            context.fill(CGRect(
                                x: decorationRunBox.frame.minX,
                                y: size.height - decorationRunBox.frame.maxY,
                                width: decorationRunBox.frame.width,
                                height: decorationRunBox.frame.height
                            ))
                        }
                    }
                }
            }
        }
        return task
    }

    func notifySelectionChanged(_ selection: RichSelection?) {
        currentSelection = selection
        selectionHandler?(selection)
        interactionDelegate?.richView(self, selectionDidChange: selection)
    }

    func presentCopyMenu(
        sourceRect: CGRect,
        selection: RichSelection
    ) {
        let copy = { [weak self] in
            guard let self else { return }
            let didHandleCopy = self.interactionDelegate?.richView(
                self,
                copy: selection
            ) == true
            if !didHandleCopy {
                UIPasteboard.general.string = selection.plainText
            }
        }
        guard let customActions = selectionMenuActions else {
            selectionMenuPresenter?.presentCopyMenu(
                from: self,
                sourceRect: sourceRect,
                copy: copy,
                selectionDidEnd: { [weak self] in self?.clearTextSelection() }
            )
            return
        }
        let actions = customActions(selection)
        selectionMenuPresenter?.presentSelectionMenu(
            from: self,
            sourceRect: sourceRect,
            actions: actions,
            selectionDidEnd: { [weak self] in self?.clearTextSelection() }
        )
    }

    func activate(_ actionIdentifier: String) {
        if let handler = simpleTextActionHandlers[actionIdentifier] {
            handler(self)
        } else if let actionHandler {
            actionHandler(self, actionIdentifier)
        } else {
            interactionDelegate?.richView(self, didActivate: actionIdentifier)
        }
    }

    func notifyUnconsumedTap() {
        interactionDelegate?.richViewDidTapUnconsumedContent(self)
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        contentMode = .topLeft
        renderLayer.richDisplayDelegate = self
        renderLayer.contentsScale = UIScreen.main.scale
        renderLayer.displaysAsynchronously = false
        renderLayer.needsDisplayOnBoundsChange = true
        selectionController.isEnabled = isTextSelectionEnabled
    }

    private func synchronizeImageLoads() {
        let sources = remoteImageSources()
        let identifiers = Set(sources.keys)
        let obsoleteIdentifiers = imageLoadTasks.keys.filter { !identifiers.contains($0) }
        for identifier in obsoleteIdentifiers {
            imageLoadTasks.removeValue(forKey: identifier)?.cancel()
        }
        loadedImages = loadedImages.filter { identifiers.contains($0.key) }
        remoteImageIdentifiers = identifiers
        guard let imageLoader else { return }
        for (identifier, source) in sources
        where loadedImages[identifier] == nil && imageLoadTasks[identifier] == nil {
            let task = imageLoader.loadImage(for: source) { [weak self] image in
                guard let self else { return }
                self.imageLoadTasks.removeValue(forKey: identifier)
                guard self.remoteImageIdentifiers.contains(identifier), let image else { return }
                self.loadedImages[identifier] = image
                self.renderLayer.setNeedsDisplay()
            }
            imageLoadTasks[identifier] = task
        }
    }

    private func remoteImageSources() -> [String: RichImageSource] {
        guard let root = currentSnapshot?.root else { return [:] }
        var result: [String: RichImageSource] = [:]
        func collect(_ element: RichElement) {
            if let image = element as? RichImageElement, image.source.loadsRemotely {
                result[image.source.identifier] = image.source
            }
            (element as? RichContainerElement)?.children.forEach(collect)
        }
        collect(root)
        return result
    }

    private func cancelImageLoads() {
        imageLoadTasks.values.forEach { $0.cancel() }
        imageLoadTasks.removeAll()
    }

    private func finishSelectionTouchRouting() {
        activeSelectionTouch = nil
        selectionTouchStartPoint = nil
        didMoveSelectionTouch = false
    }

    private func updateSimpleContentIfNeeded() {
        guard simpleContent != nil else { return }
        updateSimpleContent()
    }

    private func updateSimpleContent() {
        layoutTask?.cancel()
        usesPrecomputedLayout = false
        guard let simpleContent else {
            currentSnapshot = nil
            currentLayout = nil
            lastLayoutWidth = 0
            attachmentManager.prepareForReuse()
            selectionController.clearSelection()
            renderLayer.clearDisplayContents()
            invalidateIntrinsicContentSize()
            return
        }
        let snapshot = makeSimpleSnapshot(simpleContent)
        currentSnapshot = snapshot
        guard bounds.width > 0 else {
            currentLayout = nil
            lastLayoutWidth = 0
            invalidateIntrinsicContentSize()
            return
        }
        let layout = layoutEngine.layout(
            snapshot: snapshot,
            constrainedTo: CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        )
        apply(layout)
    }

    private func updateDocumentContent() {
        layoutTask?.cancel()
        usesPrecomputedLayout = false
        guard let documentContent else { return }
        guard bounds.width > 0 else {
            currentSnapshot = nil
            currentLayout = nil
            lastLayoutWidth = 0
            attachmentManager.prepareForReuse()
            selectionController.clearSelection()
            renderLayer.clearDisplayContents()
            invalidateIntrinsicContentSize()
            return
        }
        scheduleLayout(for: makeDocumentSnapshot(documentContent, constrainedWidth: bounds.width))
    }

    private func makeDocumentSnapshot(
        _ content: DocumentContent,
        constrainedWidth: CGFloat
    ) -> RichElementSnapshot {
        RichContentRenderer().render(
            document: content.document,
            constrainedWidth: constrainedWidth,
            configuration: content.configuration,
            resolver: content.resolver
        ).snapshot
    }

    private func makeSimpleSnapshot(_ content: SimpleContent) -> RichElementSnapshot {
        let attributedText: NSAttributedString
        switch content {
        case let .text(text):
            attributedText = makeSimpleAttributedText(from: text)
        case let .attributedText(text):
            attributedText = applyingSimpleDefaults(to: text)
        }
        let elements = makeSimpleElements(attributedText)
        return RichElementSnapshot(root: RichContainerElement(
            id: "simple-root",
            children: elements
        ))
    }

    private func makeSimpleElements(_ attributedText: NSAttributedString) -> [RichElement] {
        var inlineImages: [(image: RichAttributedInlineImage, range: NSRange)] = []
        attributedText.enumerateAttribute(
            RichAttributedInlineImage.attributeName,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, range, _ in
            guard let image = value as? RichAttributedInlineImage else { return }
            inlineImages.append((image, range))
        }
        guard !inlineImages.isEmpty else {
            return makeSimpleTextElements(attributedText)
        }

        var elements: [RichElement] = []
        var location = 0
        for (index, inlineImage) in inlineImages.enumerated() {
            if inlineImage.range.location > location {
                elements.append(contentsOf: makeSimpleTextElements(
                    attributedText.attributedSubstring(from: NSRange(
                        location: location,
                        length: inlineImage.range.location - location
                    )),
                    sourceOffset: location,
                    idPrefix: "simple-text-before-image-\(index)",
                    display: .inline
                ))
            }
            elements.append(inlineImage.image.element(
                id: "simple-inline-image-\(index)-\(inlineImage.image.id)"
            ))
            location = NSMaxRange(inlineImage.range)
        }
        if location < attributedText.length {
            elements.append(contentsOf: makeSimpleTextElements(
                attributedText.attributedSubstring(from: NSRange(
                    location: location,
                    length: attributedText.length - location
                )),
                sourceOffset: location,
                idPrefix: "simple-text-after-image",
                display: .inline
            ))
        }
        return elements
    }

    private func makeSimpleTextElements(
        _ attributedText: NSAttributedString,
        sourceOffset: Int = 0,
        idPrefix: String = "simple-text",
        display: RichElementDisplay = .block
    ) -> [RichElement] {
        guard !simpleTextActions.isEmpty else {
            return [RichTextElement(
                id: idPrefix,
                attributedText: attributedText,
                maximumNumberOfLines: numberOfLines,
                lineBreakMode: lineBreakMode,
                display: display
            )]
        }
        var elements: [RichElement] = []
        var location = 0
        let sourceRange = NSRange(location: sourceOffset, length: attributedText.length)
        let actions = simpleTextActions.compactMap { action -> SimpleTextAction? in
            let intersection = NSIntersectionRange(action.range, sourceRange)
            guard intersection.length > 0 else { return nil }
            return SimpleTextAction(
                identifier: action.identifier,
                range: NSRange(
                    location: intersection.location - sourceOffset,
                    length: intersection.length
                )
            )
        }
        for (index, action) in actions.enumerated() {
            if action.range.location > location {
                elements.append(makeSimpleTextElement(
                    id: "\(idPrefix)-\(index)",
                    text: attributedText.attributedSubstring(from: NSRange(
                        location: location,
                        length: action.range.location - location
                    ))
                ))
            }
            elements.append(RichAnchorElement(
                id: "\(idPrefix)-action-\(action.identifier)-\(index)",
                attributedText: attributedText.attributedSubstring(from: action.range),
                actionIdentifier: action.identifier,
                maximumNumberOfLines: numberOfLines,
                lineBreakMode: lineBreakMode
            ))
            location = NSMaxRange(action.range)
        }
        if location < attributedText.length {
            elements.append(makeSimpleTextElement(
                id: "\(idPrefix)-tail",
                text: attributedText.attributedSubstring(from: NSRange(
                    location: location,
                    length: attributedText.length - location
                ))
            ))
        }
        return elements
    }

    private func makeSimpleTextElement(id: String, text: NSAttributedString) -> RichTextElement {
        RichTextElement(
            id: id,
            attributedText: text,
            maximumNumberOfLines: numberOfLines,
            lineBreakMode: lineBreakMode
        )
    }

    private func removeTextActions(intersecting range: NSRange) {
        let removedIdentifiers = simpleTextActions.compactMap { action in
            NSIntersectionRange(action.range, range).length > 0 ? action.identifier : nil
        }
        simpleTextActions.removeAll { removedIdentifiers.contains($0.identifier) }
        for identifier in removedIdentifiers {
            simpleTextActionHandlers.removeValue(forKey: identifier)
        }
    }

    private func makeSimpleAttributedText(from text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle()
            ]
        )
    }

    private func applyingSimpleDefaults(to attributedText: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil { result.addAttribute(.font, value: font, range: range) }
        }
        result.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil { result.addAttribute(.foregroundColor, value: textColor, range: range) }
        }
        result.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            style.alignment = textAlignment
            style.lineBreakMode = layoutLineBreakMode
            result.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return result
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = textAlignment
        style.lineBreakMode = layoutLineBreakMode
        return style
    }

    private var layoutLineBreakMode: NSLineBreakMode {
        switch lineBreakMode {
        case .byTruncatingHead, .byTruncatingMiddle, .byTruncatingTail:
            .byWordWrapping
        default:
            lineBreakMode
        }
    }

    private func updateAccessibility(using layout: RichTextLayout) {
        var elements: [UIAccessibilityElement] = []
        for runBox in layout.textRunBoxes {
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = runBox.segments.compactMap(\.copyText).joined()
            element.accessibilityFrameInContainerSpace = runBox.frame
            element.accessibilityTraits = .staticText
            elements.append(element)
        }
        for runBox in layout.imageRunBoxes {
            guard let label = runBox.element.accessibilityLabel else { continue }
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = label
            element.accessibilityFrameInContainerSpace = runBox.frame
            element.accessibilityTraits = .image
            elements.append(element)
        }
        for runBox in layout.attachmentRunBoxes {
            guard let label = runBox.element.accessibilityLabel else { continue }
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = label
            element.accessibilityFrameInContainerSpace = runBox.contentFrame
            element.accessibilityTraits = .staticText
            elements.append(element)
        }
        accessibilityElements = elements
    }
}
