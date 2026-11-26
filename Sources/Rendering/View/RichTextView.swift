import UIKit

@MainActor
public final class RichTextView: UIView, RichRenderLayerDelegate {
    private typealias SimpleTextAction = (action: RichAction, range: NSRange)

    private enum SimpleContent {
        case text(String)
        case attributedText(NSAttributedString)

        var length: Int {
            switch self {
            case let .text(text): text.utf16.count
            case let .attributedText(text): text.length
            }
        }
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
            setSimpleContent(newValue.map(SimpleContent.text), actions: [])
        }
    }

    public var attributedText: NSAttributedString? {
        get {
            guard let simpleContent else { return nil }
            switch simpleContent {
            case let .text(text): return applyingActions(to: makeSimpleAttributedText(from: text))
            case let .attributedText(text): return applyingActions(to: text)
            }
        }
        set {
            setSimpleContent(newValue.map { .attributedText(NSAttributedString(attributedString: $0)) }, actions: [])
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
            if isTextSelectionEnabled {
                ensureSelectionController().isEnabled = true
            } else {
                selectionController?.isEnabled = false
            }
        }
    }
    public var initialSelectionPolicy: RichInitialSelectionPolicy = .allContent

    public weak var interactionDelegate: RichTextViewInteractionDelegate?
    /// Handles events after a range-specific closure and before the legacy handler or delegate.
    public var actionEventHandler: ((RichTextView, RichActionEvent) -> Void)?
    public var actionHandler: ((RichTextView, String) -> Void)?
    public var didDisplay: (() -> Void)?
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

    /// Kept for source compatibility. Bitmap updates always preserve the last completed frame.
    public var preservesRenderedContentDuringAsyncUpdates = true

    public private(set) var currentLayout: RichTextLayout?
    public private(set) var currentSnapshot: RichElementSnapshot?
    public private(set) var currentSelection: RichSelection?

    lazy var codeCopyPasteboard: UIPasteboard = .general

    private let layoutEngine: RichTextLayoutEngine
    private lazy var attachmentManager = RichAttachmentManager(hostView: self)
    private var selectionController: RichSelectionController?
    private let contentTapDelegate = RichContentTapDelegate()
    private lazy var contentTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleContentTap(_:)))
        gesture.delegate = contentTapDelegate
        return gesture
    }()
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
    private var memoryWarningObserver: NSObjectProtocol?
    private var documentRenderer: RichContentRenderer?
    // Core Animation can request tiles on a background thread long after display() returns.
    private var currentTileTask: RichRenderLayerDisplayTask?
    private var imageRevision: UInt = 0

    // swiftlint:disable:next force_cast
    private var renderLayer: RichRenderLayer { layer as! RichRenderLayer }

    public init(
        frame: CGRect = .zero,
        layoutEngine: RichTextLayoutEngine = .shared,
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
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
        layoutTask?.cancel()
        if let selectionController {
            if Thread.isMainThread {
                MainActor.assumeIsolated { selectionController.removeSelectionViews() }
            } else {
                Task { @MainActor in selectionController.removeSelectionViews() }
            }
        }
    }

    public func apply(_ snapshot: RichElementSnapshot) {
        resetDocumentContent()
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

    public func setText(_ text: String, actions: [(action: RichAction, range: NSRange)]) {
        setSimpleContent(.text(text), actions: actions)
    }

    public func setAttributedText(_ attributedText: NSAttributedString, actions: [(action: RichAction, range: NSRange)] = []) {
        setSimpleContent(.attributedText(NSAttributedString(attributedString: attributedText)), actions: actions)
    }

    private func setSimpleContent(_ content: SimpleContent?, actions: [SimpleTextAction]) {
        resetDocumentContent()
        simpleContent = content
        replaceSimpleTextActions(actions)
    }

    private func isValidActionRange(_ range: NSRange) -> Bool {
        guard let length = simpleContent?.length else { return false }
        return range.location >= 0 && range.length > 0 && range.location <= length && range.length <= length - range.location
    }

    public func setTextAction(_ actionIdentifier: String, range: NSRange) {
        guard let action = RichAction(legacyIdentifier: actionIdentifier), isValidActionRange(range) else { return }
        removeTextActions(intersecting: range)
        simpleTextActions.append((action, range))
        updateSimpleContent()
    }

    public func setTextAction(
        range: NSRange,
        handler: @escaping (RichTextView) -> Void
    ) {
        let identifier = "simple-range-\(range.location)-\(range.length)"
        setTextAction(identifier, range: range)
        guard simpleTextActions.contains(where: { $0.action.legacyIdentifier == identifier }) else {
            return
        }
        simpleTextActionHandlers[identifier] = handler
    }

    public func setTextActions(_ actions: [(identifier: String, range: NSRange)]) {
        guard simpleContent != nil else { return }
        replaceSimpleTextActions(actions.compactMap { identifier, range in
            RichAction(legacyIdentifier: identifier).map { ($0, range) }
        })
    }

    private func replaceSimpleTextActions(_ actions: [SimpleTextAction]) {
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        var previousEnd = 0
        for entry in actions.sorted(by: { $0.range.location < $1.range.location }) {
            guard isValidActionRange(entry.range), entry.range.location >= previousEnd else { continue }
            simpleTextActions.append(entry)
            previousEnd = NSMaxRange(entry.range)
        }
        updateSimpleContent()
    }

    public func removeAllTextActions() {
        guard !simpleTextActions.isEmpty else { return }
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        updateSimpleContent()
    }

    public func action(at point: CGPoint) -> RichAction? {
        currentLayout?.interactiveRegion(at: point)?.action
    }

    public func actionIdentifier(at point: CGPoint) -> String? {
        action(at: point)?.legacyIdentifier
    }

    private func scheduleLayout(for snapshot: RichElementSnapshot) {
        currentSnapshot = snapshot
        generation &+= 1
        let requestedGeneration = generation
        let constrainedSize = bounds.size
        layoutTask?.cancel()
        guard laysOutAsynchronously else {
            installLayout(layoutEngine.layout(snapshot: snapshot, constrainedTo: constrainedSize))
            return
        }
        layoutTask = Task { [weak self, layoutEngine] in
            let layout = await Task.detached(priority: .userInitiated) {
                layoutEngine.layout(snapshot: snapshot, constrainedTo: constrainedSize)
            }.value
            guard !Task.isCancelled else { return }
            guard let self, self.generation == requestedGeneration else { return }
            self.installLayout(layout)
        }
    }

    public func apply(_ updates: [RichElementUpdate]) {
        guard let currentSnapshot else { return }
        apply(currentSnapshot.applying(updates))
    }

    public func apply(_ snapshot: RichElementSnapshot, layout: RichTextLayout) {
        precondition(snapshot.root.id == layout.rootElementID, "Snapshot and layout must have the same root ID")
        resetDocumentContent()
        simpleContent = nil
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        currentSnapshot = snapshot
        usesPrecomputedLayout = true
        installLayout(layout)
    }

    public func apply(_ layout: RichTextLayout) {
        if documentContent != nil {
            resetDocumentContent()
            currentSnapshot = nil
            usesPrecomputedLayout = true
        }
        installLayout(layout)
    }

    private func installLayout(_ layout: RichTextLayout) {
        generation &+= 1
        layoutTask?.cancel()
        currentLayout = layout
        lastLayoutWidth = layout.constrainedSize.width
        attachmentManager.apply(layout.attachmentRunBoxes)
        synchronizeImageLoads()
        selectionController?.apply(layout: layout)
        updateAccessibility(using: layout)
        renderLayer.setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    public func prepareForReuse() {
        renderLayer.updateVisibleRect(nil)
        renderLayer.suspendsDisplay = false
        generation &+= 1
        layoutTask?.cancel()
        layoutTask = nil
        currentSnapshot = nil
        currentLayout = nil
        resetDocumentContent()
        simpleContent = nil
        simpleTextActions.removeAll()
        simpleTextActionHandlers.removeAll()
        lastLayoutWidth = 0
        usesPrecomputedLayout = false
        attachmentManager.prepareForReuse()
        cancelImageLoads()
        loadedImages.removeAll()
        remoteImageIdentifiers.removeAll()
        selectionController?.apply(layout: nil)
        accessibilityElements = nil
        clearDisplayContents()
    }

    /// Supply the scroll viewport in this view's bounds coordinates to bound bitmap memory for tall documents.
    /// Pass nil to restore Core Animation's automatic tiling.
    public func updateVisibleRect(_ rect: CGRect?) {
        renderLayer.updateVisibleRect(rect)
    }

    public func clearTextSelection() {
        selectionController?.clearSelection()
    }

    public func isSelectionHandleTouch(atWindowPoint windowPoint: CGPoint) -> Bool {
        selectionController?.isSelectionHandleTouch(atWindowPoint: windowPoint) == true
    }

    public func prioritizeSelection(over competingGestureRecognizer: UIGestureRecognizer) {
        ensureSelectionController().prioritizeSelection(over: competingGestureRecognizer)
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

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        selectionController?.didMoveToWindow()
        if window != nil, renderLayer.suspendsDisplay {
            renderLayer.suspendsDisplay = false
            synchronizeImageLoads()
            renderLayer.setNeedsDisplay()
        }
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        selectionController?.updateAppearance()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true else { return }
        renderLayer.setNeedsDisplay()
        selectionController?.updateAppearance()
    }

    func newRenderDisplayTask(forTiling: Bool) -> RichRenderLayerDisplayTask {
        let task = newRenderDisplayTask()
        if forTiling {
            currentTileTask = task
        } else {
            task.didDisplay = { [weak self] in
                self?.currentTileTask = nil
                self?.didDisplay?()
            }
        }
        return task
    }

    func newRenderDisplayTask() -> RichRenderLayerDisplayTask {
        let task = RichRenderLayerDisplayTask()
        guard let layout = currentLayout else { return task }
        let loadedImages = loadedImages
        let displayTraits = traitCollection
        task.requiresAtomicBitmap = animatesStreamingChanges
        task.animatesStreamingChanges = animatesStreamingChanges && window != nil && !UIAccessibility.isReduceMotionEnabled
        task.layout = layout
        task.traits = displayTraits
        task.imageRevision = imageRevision
        task.didDisplay = { [weak self] in self?.didDisplay?() }
        task.display = { context, size, isCancelled in
            displayTraits.performAsCurrent {
                layout.draw(in: context, size: size, loadedImages: loadedImages, isCancelled: isCancelled)
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

    private func trigger(_ region: RichInteractiveRegion, via trigger: RichActionEvent.Trigger) {
        activate(region.event(trigger: trigger))
    }

    func activate(_ event: RichActionEvent, sourceLayout: RichTextLayout? = nil) {
        let layout = sourceLayout ?? currentLayout
        if case let .copyCode(nodeID) = event.action.kind,
           let code = layout?.codeBlockTextByID[nodeID],
           interactionDelegate?.richView(self, copyCode: code, nodeID: nodeID) != true {
            codeCopyPasteboard.string = code
        }
        let actionIdentifier = event.action.legacyIdentifier
        if let handler = simpleTextActionHandlers[actionIdentifier] {
            handler(self)
        } else if let actionEventHandler {
            actionEventHandler(self, event)
        } else if let actionHandler {
            actionHandler(self, actionIdentifier)
        } else {
            interactionDelegate?.richView(self, didTrigger: event)
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
        addGestureRecognizer(contentTapGesture)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window == nil else { return }
                self.renderLayer.suspendsDisplay = true
                self.cancelImageLoads()
                self.remoteImageIdentifiers.removeAll()
                self.loadedImages.removeAll()
                self.clearDisplayContents()
            }
        }
    }

    private func clearDisplayContents() {
        currentTileTask = nil
        renderLayer.clearDisplayContents()
    }

    private func synchronizeImageLoads() {
        guard !renderLayer.suspendsDisplay else { return }
        let sources = remoteImageSources()
        let identifiers = Set(sources.keys)
        let obsoleteIdentifiers = imageLoadTasks.keys.filter { !identifiers.contains($0) }
        for identifier in obsoleteIdentifiers {
            imageLoadTasks.removeValue(forKey: identifier)?.cancel()
        }
        let previousCount = loadedImages.count
        loadedImages = loadedImages.filter { identifiers.contains($0.key) }
        if loadedImages.count != previousCount { imageRevision &+= 1 }
        remoteImageIdentifiers = identifiers
        guard let imageLoader else { return }
        for (identifier, source) in sources
        where loadedImages[identifier] == nil && imageLoadTasks[identifier] == nil {
            let task = imageLoader.loadImage(for: source) { [weak self] image in
                guard let self else { return }
                self.imageLoadTasks.removeValue(forKey: identifier)
                guard self.remoteImageIdentifiers.contains(identifier), let image else { return }
                self.imageRevision &+= 1
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

    private func ensureSelectionController() -> RichSelectionController {
        if let selectionController { return selectionController }
        let controller = RichSelectionController(hostView: self)
        selectionController = controller
        return controller
    }

    @objc private func handleContentTap(_ gesture: UITapGestureRecognizer) {
        handleContentTap(at: gesture.location(in: self))
    }

    func handleContentTap(at point: CGPoint) {
        if currentSelection != nil {
            clearTextSelection()
        } else if let region = currentLayout?.interactiveRegion(at: point) {
            trigger(region, via: .tap)
        } else {
            notifyUnconsumedTap()
        }
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
            accessibilityElements = nil
            lastLayoutWidth = 0
            attachmentManager.prepareForReuse()
            selectionController?.apply(layout: nil)
            clearDisplayContents()
            invalidateIntrinsicContentSize()
            return
        }
        let snapshot = makeSimpleSnapshot(simpleContent)
        currentSnapshot = snapshot
        guard bounds.width > 0 else {
            currentLayout = nil
            accessibilityElements = nil
            selectionController?.apply(layout: nil)
            lastLayoutWidth = 0
            invalidateIntrinsicContentSize()
            return
        }
        let layout = layoutEngine.layout(
            snapshot: snapshot,
            constrainedTo: CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        )
        installLayout(layout)
    }

    private func updateDocumentContent() {
        layoutTask?.cancel()
        usesPrecomputedLayout = false
        guard let documentContent else { return }
        guard bounds.width > 0 else {
            lastLayoutWidth = 0
            return
        }
        scheduleLayout(for: makeDocumentSnapshot(documentContent, constrainedWidth: bounds.width))
    }

    private func resetDocumentContent() {
        documentContent = nil
        documentRenderer?.reset()
        documentRenderer = nil
    }

    private func makeDocumentSnapshot(
        _ content: DocumentContent,
        constrainedWidth: CGFloat
    ) -> RichElementSnapshot {
        let renderer = documentRenderer ?? RichContentRenderer()
        documentRenderer = renderer
        return renderer.render(
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
        let elements = makeSimpleElements(applyingActions(to: attributedText))
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
            return [makeSimpleTextElement(attributedText)]
        }

        var elements: [RichElement] = []
        var location = 0
        for (index, inlineImage) in inlineImages.enumerated() {
            if inlineImage.range.location > location {
                elements.append(makeSimpleTextElement(
                    attributedText.attributedSubstring(from: NSRange(
                        location: location,
                        length: inlineImage.range.location - location
                    )),
                    id: "simple-text-before-image-\(index)",
                    display: .inline
                ))
            }
            elements.append(inlineImage.image.element(
                id: "simple-inline-image-\(index)-\(inlineImage.image.id)",
                action: RichAction.from(attributes: attributedText.attributes(at: inlineImage.range.location, effectiveRange: nil)) ?? inlineImage.image.action
            ))
            location = NSMaxRange(inlineImage.range)
        }
        if location < attributedText.length {
            elements.append(makeSimpleTextElement(
                attributedText.attributedSubstring(from: NSRange(
                    location: location,
                    length: attributedText.length - location
                )),
                id: "simple-text-after-image",
                display: .inline
            ))
        }
        return elements
    }

    private func applyingActions(to text: NSAttributedString) -> NSAttributedString {
        guard !simpleTextActions.isEmpty else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        for entry in simpleTextActions {
            result.addAttribute(.richAction, value: entry.action, range: entry.range)
        }
        return result
    }

    private func makeSimpleTextElement(
        _ text: NSAttributedString,
        id: String = "simple-text",
        display: RichElementDisplay = .block
    ) -> RichTextElement {
        RichTextElement(
            id: id,
            attributedText: text,
            maximumNumberOfLines: numberOfLines,
            lineBreakMode: lineBreakMode,
            display: display
        )
    }

    private func removeTextActions(intersecting range: NSRange) {
        simpleTextActions.removeAll { entry in
            guard NSIntersectionRange(entry.range, range).length > 0 else { return false }
            simpleTextActionHandlers.removeValue(forKey: entry.action.legacyIdentifier)
            return true
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
        accessibilityElements = layout.accessibilityElements(for: currentSnapshot, in: self,
            attachmentView: attachmentManager.view(for:)) { [weak self, weak layout] region in
                guard let self, let layout, currentLayout === layout else { return false }
                trigger(region, via: .accessibility)
                return true
            }
    }
}

@MainActor
extension RichTextLayout {
    func accessibilityElements(for snapshot: RichElementSnapshot?, in container: UIView, origin: CGPoint = .zero,
                               attachmentView: (String) -> UIView?,
                               activate: @escaping (RichInteractiveRegion) -> Bool) -> [Any] {
        var elements: [Any] = []

        func appendLabel(_ label: String?, frame: CGRect, traits: UIAccessibilityTraits = .staticText) {
            guard let label, !label.isEmpty, !frame.isNull else { return }
            let element = UIAccessibilityElement(accessibilityContainer: container)
            element.accessibilityLabel = label
            element.accessibilityFrameInContainerSpace = frame.offsetBy(dx: origin.x, dy: origin.y)
            element.accessibilityTraits = traits
            elements.append(element)
        }

        func appendLink(_ region: RichInteractiveRegion, label: String?) {
            let element = RichActionAccessibilityElement(accessibilityContainer: container)
            element.accessibilityLabel = label.flatMap { $0.isEmpty ? nil : $0 } ?? region.action.legacyIdentifier
            element.accessibilityFrameInContainerSpace = region.rects.reduce(CGRect.null) { $0.union($1) }.offsetBy(dx: origin.x, dy: origin.y)
            element.accessibilityTraits = .link
            element.onActivate = { activate(region) }
            elements.append(element)
        }

        let regionsByID = Dictionary(grouping: interactiveRegions, by: \.elementID)
        for box in runBoxes {
            if let run = box as? RichTextRunBox {
                guard !run.interactiveRegions.isEmpty else {
                    appendLabel(run.segments.compactMap(\.copyText).joined(), frame: run.frame)
                    continue
                }
                for segment in run.segments {
                    func appendStaticText(from start: Int, to end: Int) {
                        guard end > start else { return }
                        let range = NSRange(location: start - run.globalRange.location, length: end - start)
                        let frame = run.layout.selectionRects(for: range).reduce(CGRect.null) { $0.union($1) }
                        let label = range == segment.range ? segment.copyText : (run.text.string as NSString).substring(with: range)
                        appendLabel(label, frame: frame.offsetBy(dx: run.frame.minX, dy: run.frame.minY))
                    }

                    var cursor = segment.globalRange.location
                    for region in regionsByID[segment.elementID] ?? [] {
                        appendStaticText(from: cursor, to: region.range.location)
                        let local = NSRange(location: region.range.location - run.globalRange.location, length: region.range.length)
                        let text = (run.text.string as NSString).substring(with: local)
                        let label: String?
                        if text == "\u{FFFC}" {
                            let image = snapshot?.element(withID: segment.elementID) as? RichImageElement
                            label = image?.accessibilityLabel ?? segment.copyText
                        } else {
                            label = text
                        }
                        appendLink(region, label: label)
                        cursor = NSMaxRange(region.range)
                    }
                    appendStaticText(from: cursor, to: NSMaxRange(segment.globalRange))
                }
            } else if let image = box as? RichImageRunBox {
                if let region = regionsByID[image.id]?.first {
                    appendLink(region, label: image.element.accessibilityLabel ?? image.element.copyText)
                } else {
                    appendLabel(image.element.accessibilityLabel, frame: image.frame, traits: .image)
                }
            } else if let attachment = box as? RichAttachmentRunBox {
                if attachment.element.provider is RichTableViewProvider, let table = attachmentView(attachment.id) {
                    elements.append(table)
                } else if let code = attachment.element.provider as? RichCodeBlockViewProvider,
                          let region = regionsByID[code.copyElementID]?.first {
                    appendLink(region, label: "Copy")
                } else {
                    appendLabel(attachment.element.accessibilityLabel, frame: attachment.contentFrame)
                }
            }
        }
        return elements
    }
}

extension UIView {
    var enclosingRichTextView: RichTextView? {
        var view = superview
        while let current = view {
            if let richTextView = current as? RichTextView { return richTextView }
            view = current.superview
        }
        return nil
    }
}

private final class RichActionAccessibilityElement: UIAccessibilityElement {
    var onActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onActivate?() ?? false
    }
}

@MainActor
private final class RichContentTapDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let host = gestureRecognizer.view as? RichTextView else { return false }
        return host.currentSelection != nil || touch.view === host
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let host = gestureRecognizer.view as? RichTextView, host.currentSelection == nil, let otherView = otherGestureRecognizer.view else { return false }
        return otherView !== host && otherView.isDescendant(of: host)
    }
}
