import UIKit

// Digests include attribute boundaries and values. NSAttributedString.hash alone
// does not distinguish an edit to the attributes of an otherwise identical string.
private func textFingerprint(_ text: NSAttributedString, length: Int) -> Int {
    var hash = Hasher()
    hash.combine(length)
    let range = NSRange(location: 0, length: length)
    let string = text.string as NSString
    hash.combine(string.substring(with: range))
    text.enumerateAttributes(in: range) { attributes, runRange, _ in
        hash.combine(runRange)
        for key in attributes.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            hash.combine(key)
            hash.combine((attributes[key] as? NSObject)?.hash)
        }
    }
    return hash.finalize()
}

struct DisplaySummary {
    private enum DrawingIdentity: Equatable {
        case text(UUID), image(UUID), decoration(Int), attachment, unknown(UUID)

        init(_ run: RichRunBox) {
            switch run {
            case let text as RichTextRunBox: self = .text(text.layout.drawingID)
            case let image as RichImageRunBox: self = .image(image.element.drawingID)
            case is RichAttachmentRunBox: self = .attachment
            case let decoration as RichDecorationRunBox:
                var hash = Hasher()
                switch decoration.decoration {
                case let .background(color, radius):
                    hash.combine(0)
                    hash.combine(color)
                    hash.combine(radius)
                case let .topRoundedBackground(color, radius):
                    hash.combine(1)
                    hash.combine(color)
                    hash.combine(radius)
                case let .borderedBackground(color, radius, border, width):
                    hash.combine(2)
                    hash.combine(color)
                    hash.combine(radius)
                    hash.combine(border)
                    hash.combine(width)
                case let .verticalGradient(top, bottom):
                    hash.combine(3)
                    hash.combine(top)
                    hash.combine(bottom)
                case let .leadingRule(color, width):
                    hash.combine(4)
                    hash.combine(color)
                    hash.combine(width)
                case let .horizontalRule(color):
                    hash.combine(5)
                    hash.combine(color)
                case let .listMarker(text, width):
                    hash.combine(6)
                    hash.combine(textFingerprint(text, length: text.length))
                    hash.combine(width)
                }
                self = .decoration(hash.finalize())
            default: self = .unknown(UUID())
            }
        }
    }

    private struct Run: Equatable {
        let id: String
        let frame: CGRect
        let identity: DrawingIdentity
    }

    private struct TextTail {
        let run: Run
        let length: Int
        let fingerprint: Int
        let range: NSRange
        let rects: [CGRect]
    }

    private let rootElementID: String
    private let width: CGFloat
    private let traits: UITraitCollection?
    private let imageRevision: UInt
    private let runs: [Run]
    private let tails: [TextTail]?

    init?(_ task: RichRenderLayerDisplayTask, reusing previous: DisplaySummary? = nil) {
        guard let layout = task.layout else { return nil }
        rootElementID = layout.rootElementID
        width = layout.constrainedSize.width
        traits = task.traits
        imageRevision = task.imageRevision
        runs = layout.runBoxes.map { Run(id: $0.id, frame: $0.frame, identity: DrawingIdentity($0)) }
        tails = task.animatesStreamingChanges ? layout.textRunBoxes.enumerated().map { index, text in
            let run = Run(id: text.id, frame: text.frame, identity: .text(text.layout.drawingID))
            if let old = previous?.tails, old.indices.contains(index), old[index].run == run { return old[index] }
            let length = text.text.length
            let start = text.layout.lines.last?.range.location ?? length
            let range = NSRange(location: start, length: length - start)
            return TextTail(run: run, length: length, fingerprint: textFingerprint(text.text, length: length),
                            range: range, rects: text.layout.selectionRects(for: range))
        } : nil
    }

    private func matches(_ previous: Self) -> Bool {
        rootElementID == previous.rootElementID && width == previous.width && traits == previous.traits
    }

    func unchangedPrefixHeight(comparedTo previous: Self?) -> CGFloat {
        guard let previous, matches(previous), imageRevision == previous.imageRevision else { return 0 }
        var index = 0
        while index < min(runs.count, previous.runs.count), runs[index] == previous.runs[index] { index += 1 }
        // Decorations can overlap earlier children. Include both the erased and the new suffix.
        return min(runs[index...].lazy.map(\.frame.minY).min() ?? .greatestFiniteMagnitude,
                   previous.runs[index...].lazy.map(\.frame.minY).min() ?? .greatestFiniteMagnitude)
    }

    func appendedTextRects(in layout: RichTextLayout, comparedTo previous: Self?) -> [CGRect]? {
        guard let previous, matches(previous), let oldTails = previous.tails, let tails,
              tails.count == layout.textRunBoxes.count, tails.count >= oldTails.count else { return nil }
        var rects: [CGRect] = []
        for (index, text) in layout.textRunBoxes.enumerated() {
            var start = 0
            if oldTails.indices.contains(index) {
                let old = oldTails[index]
                if old.run == tails[index].run { continue }
                start = old.length
                guard old.run.id == text.id, old.run.frame.origin == text.frame.origin,
                      text.text.length >= start, textFingerprint(text.text, length: start) == old.fingerprint,
                      text.layout.selectionRects(for: old.range) == old.rects else { return nil }
            }
            let range = NSRange(location: start, length: text.text.length - start)
            rects += text.layout.selectionRects(for: range).map { $0.offsetBy(dx: text.frame.minX, dy: text.frame.minY) }
        }
        return rects
    }
}

final class RichRenderLayerDisplayTask: @unchecked Sendable {
    var display: ((CGContext, CGSize, () -> Bool) -> Void)?
    var animatesStreamingChanges = false
    // Streaming uses atomic replacement even when Reduce Motion suppresses the fade.
    var requiresAtomicBitmap = false
    var layout: RichTextLayout?
    var traits: UITraitCollection?
    var imageRevision: UInt = 0
    var didDisplay: (() -> Void)?
}

@MainActor
protocol RichRenderLayerDelegate: AnyObject {
    func newRenderDisplayTask(forTiling: Bool) -> RichRenderLayerDisplayTask
}

private struct FadeRegion {
    static let duration: CFTimeInterval = 0.25
    let rect: CGRect
    let start: CFTimeInterval
    var end: CFTimeInterval { start + Self.duration }
}

final class RichTiledLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }

    // Presentation copies and concurrent CA callbacks see one coherent generation.
    // The view owns the current task. Only an in-flight tile draw holds it strongly.
    private final class Source {
        let lock = NSLock()
        weak var task: RichRenderLayerDisplayTask?
        var size = CGSize.zero
        var fades: [FadeRegion] = []
        var firstDraw: (() -> Void)?
    }
    private let source: Source

    override init() {
        source = Source()
        super.init()
        tileSize = CGSize(width: 512, height: 512)
        contentsGravity = .topLeft
        isOpaque = false
    }

    override init(layer: Any) {
        source = (layer as? RichTiledLayer)?.source ?? Source()
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(task: RichRenderLayerDisplayTask, size: CGSize) {
        update(task: task, size: size, fades: [], firstDraw: nil)
    }

    fileprivate func update(task: RichRenderLayerDisplayTask, size: CGSize, fades: [FadeRegion], firstDraw: (() -> Void)?) {
        source.lock.lock()
        defer { source.lock.unlock() }
        source.task = task
        source.size = size
        source.fades = fades
        source.firstDraw = firstDraw
    }

    override func draw(in context: CGContext) {
        source.lock.lock()
        let task = source.task
        let size = source.size
        let fades = source.fades
        source.lock.unlock()
        guard let task, let display = task.display else { return }
        autoreleasepool {
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            display(context, size, { false })
            context.restoreGState()

            // Fade in the tile's own small backing store, without a document-sized mask.
            let now = CACurrentMediaTime()
            context.saveGState()
            context.setBlendMode(.destinationOut)
            for fade in fades where fade.end > now && fade.rect.intersects(context.boundingBoxOfClipPath) {
                context.setFillColor(gray: 0, alpha: min(1, (fade.end - now) / FadeRegion.duration))
                context.fill(fade.rect)
            }
            context.restoreGState()
        }
        source.lock.lock()
        let callback = source.task === task ? source.firstDraw : nil
        if callback != nil { source.firstDraw = nil }
        source.lock.unlock()
        if let callback { DispatchQueue.main.async(execute: callback) }
    }
}

final class RichRenderLayer: CALayer {
    weak var richDisplayDelegate: RichRenderLayerDelegate?
    var displaysAsynchronously = false
    var suspendsDisplay = false

    private static let tileThreshold: CGFloat = 1_024
    private static let displayQueue = DispatchQueue(label: "io.github.felikslv01.rich-text-view.display", qos: .userInitiated)
    private let guardLock = NSLock()
    private var generation: UInt = 0
    private var pendingBitmapTask: RichRenderLayerDisplayTask?
    private var nativeTask: RichRenderLayerDisplayTask?
    private var requestedViewport: CGRect?
    private weak var stripTask: RichRenderLayerDisplayTask?
    private var strips: [Int: CALayer] = [:]
    private var idleStrips: [CALayer] = []
    private static let stripHeight: CGFloat = 512
    private var tiledLayer: RichTiledLayer?
    private var displayedSummary: DisplaySummary?
    private var fadeRegions: [FadeRegion] = []
    private weak var streamingMask: CALayer?

    override func setNeedsDisplay() {
        invalidateDisplay()
        super.setNeedsDisplay()
    }

    override func display() {
        let size = bounds.size
        guard !suspendsDisplay, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let tiled = size.width > Self.tileThreshold || size.height > Self.tileThreshold
        guard let task = MainActor.assumeIsolated({ richDisplayDelegate?.newRenderDisplayTask(forTiling: tiled) }),
              task.display != nil else { return }
        invalidateDisplay()
        let token = currentGeneration()
        let scale = max(1, contentsScale)
        if size.height > Self.tileThreshold, let requestedViewport {
            stripTask = task
            updateStrips(in: requestedViewport, task: task, redraw: true)
            task.didDisplay?()
            return
        }
        stripTask = nil
        if tiled {
            displayTiled(task, size: size, scale: scale, token: token)
            return
        }

        if !displaysAsynchronously && !task.requiresAtomicBitmap && !task.animatesStreamingChanges {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            nativeTask = task
            super.display()
            nativeTask = nil
            tiledLayer?.removeFromSuperlayer()
            tiledLayer = nil
            removeStrips()
            clearStreamingMask()
            displayedSummary = nil
            fadeRegions.removeAll()
            CATransaction.commit()
            task.didDisplay?()
            return
        }

        pendingBitmapTask = task
        let render = { [weak self, weak task] () -> CGImage? in
            let cancelled = { [weak self] in self?.currentGeneration() != token }
            guard let display = task?.display, !cancelled() else { return nil }
            return Self.renderImage(size: size, scale: scale) { display($0, size, cancelled) }
        }
        let install = { [weak self, weak task] (image: CGImage?) in
            guard let self, let task, self.currentGeneration() == token else { return }
            self.pendingBitmapTask = nil
            guard let image else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.removeStrips()
            self.contents = image
            self.tiledLayer?.removeFromSuperlayer()
            self.tiledLayer = nil
            self.updateSummary(for: task)
            self.applyBitmapFade()
            CATransaction.commit()
            task.didDisplay?()
        }
        if displaysAsynchronously {
            Self.displayQueue.async {
                let image = render()
                DispatchQueue.main.async { install(image) }
            }
        } else {
            install(render())
        }
    }

    override func draw(in context: CGContext) {
        guard let display = nativeTask?.display else { return }
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        display(context, bounds.size, { false })
        context.restoreGState()
    }

    func updateVisibleRect(_ rect: CGRect?) {
        if let rect {
            // UIKit can report empty geometry while changing windows or rotating.
            guard !rect.isNull, !rect.isInfinite, !rect.isEmpty,
                  rect.minX.isFinite, rect.maxX.isFinite, rect.minY.isFinite, rect.maxY.isFinite else { return }
        }
        guard requestedViewport != rect else { return }
        let changedMode = (requestedViewport == nil) != (rect == nil)
        requestedViewport = rect
        guard bounds.height > Self.tileThreshold, !suspendsDisplay else { return }
        if changedMode { setNeedsDisplay() }
        else if let rect, let task = stripTask, !needsDisplay() {
            updateStrips(in: rect, task: task, redraw: false)
        }
    }

    private func updateStrips(in rect: CGRect, task: RichRenderLayerDisplayTask, redraw: Bool) {
        guard let display = task.display else { return }
        let size = bounds.size
        let documentBounds = CGRect(origin: .zero, size: size)
        let keep = rect.insetBy(dx: 0, dy: -rect.height)
        let prefetch = documentBounds.intersection(rect.insetBy(dx: 0, dy: -0.5 * rect.height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (index, strip) in strips where !keep.intersects(strip.frame) || !documentBounds.intersects(strip.frame) {
            strip.contents = nil
            strip.removeFromSuperlayer()
            strips.removeValue(forKey: index)
            if idleStrips.count < 6 { idleStrips.append(strip) }
        }
        var required = redraw ? Set(strips.keys) : Set<Int>()
        if !prefetch.isEmpty {
            let first = Int(floor(prefetch.minY / Self.stripHeight))
            let end = Int(ceil(prefetch.maxY / Self.stripHeight))
            required.formUnion(first..<end)
        }
        let scale = max(1, contentsScale)
        for index in required where redraw || strips[index] == nil {
            let y = CGFloat(index) * Self.stripHeight
            let frame = CGRect(x: 0, y: y, width: size.width, height: min(Self.stripHeight, size.height - y))
            let image = Self.renderImage(size: frame.size, scale: scale) { context in
                context.translateBy(x: 0, y: frame.maxY - size.height)
                display(context, size, { false })
            }
            let strip = strips[index] ?? idleStrips.popLast() ?? CALayer()
            strip.frame = frame
            strip.contentsScale = scale
            strip.contents = image
            if strip.superlayer == nil { insertSublayer(strip, at: 0) }
            strips[index] = strip
        }
        if redraw {
            contents = nil
            tiledLayer?.removeFromSuperlayer()
            tiledLayer = nil
            displayedSummary = nil
            fadeRegions.removeAll()
            clearStreamingMask()
        }
    }

    private func removeStrips() {
        guard !strips.isEmpty || !idleStrips.isEmpty else { return }
        for strip in strips.values {
            strip.contents = nil
            strip.removeFromSuperlayer()
        }
        strips.removeAll()
        idleStrips.removeAll()
    }

    private func displayTiled(_ task: RichRenderLayerDisplayTask, size: CGSize, scale: CGFloat, token: UInt) {
        let tile = tiledLayer ?? RichTiledLayer()
        let previous = displayedSummary
        let previousFades = fadeRegions
        updateSummary(for: task)
        let sameWidthAndScale = tiledLayer != nil && tile.bounds.width == size.width && tile.contentsScale == scale
        let prefix = sameWidthAndScale ? displayedSummary?.unchangedPrefixHeight(comparedTo: previous) ?? 0 : 0
        // Include newly exposed rows even if the text layout itself hasn't changed.
        let dirtyY = max(0, min(prefix, tile.bounds.height))
        let dirty = CGRect(x: 0, y: dirtyY, width: size.width, height: max(0, size.height - dirtyY))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clearStreamingMask()
        tile.contentsScale = scale
        tile.frame = CGRect(origin: .zero, size: size)
        let finish = { [weak self, weak task] in
            guard let self, self.currentGeneration() == token else { return }
            // Keep the small backing bitmap during the handoff to native tiles.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.contents = nil
            self.removeStrips()
            CATransaction.commit()
            task?.didDisplay?()
        }
        // A second update can arrive before CA draws its first tile.
        let waitsForTile = !dirty.isEmpty || contents != nil
        tile.update(task: task, size: size, fades: fadeRegions, firstDraw: waitsForTile ? finish : nil)
        if tiledLayer == nil {
            tiledLayer = tile
            insertSublayer(tile, at: 0)
        }
        if !dirty.isEmpty { tile.setNeedsDisplay(dirty) }
        // An interrupted fade may have left partially transparent pixels above the new dirty suffix.
        for region in previousFades where !dirty.contains(region.rect) {
            tile.setNeedsDisplay(region.rect)
        }
        CATransaction.commit()
        refreshFadingTiles(token: token)
        if !waitsForTile { finish() }
    }

    private func updateSummary(for task: RichRenderLayerDisplayTask) {
        let previous = displayedSummary
        displayedSummary = DisplaySummary(task, reusing: previous)
        guard task.animatesStreamingChanges, let layout = task.layout,
              let rects = displayedSummary?.appendedTextRects(in: layout, comparedTo: previous) else {
            fadeRegions.removeAll()
            return
        }
        let now = CACurrentMediaTime()
        fadeRegions.removeAll { $0.end <= now }
        for (index, rect) in rects.enumerated() {
            fadeRegions.append(FadeRegion(rect: rect, start: now + 0.1 * Double(index) / Double(rects.count)))
        }
    }

    private func refreshFadingTiles(token: UInt) {
        guard !fadeRegions.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self] in
            guard let self, self.currentGeneration() == token, let tile = self.tiledLayer else { return }
            for region in self.fadeRegions { tile.setNeedsDisplay(region.rect) }
            self.fadeRegions.removeAll { $0.end <= CACurrentMediaTime() }
            self.refreshFadingTiles(token: token)
        }
    }

    private func applyBitmapFade() {
        clearStreamingMask()
        guard !fadeRegions.isEmpty, mask == nil else { return }
        let mask = CALayer()
        mask.frame = bounds
        let base = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(mask.bounds)
        for region in fadeRegions {
            path.addRect(region.rect)
            let reveal = CALayer()
            reveal.frame = region.rect
            reveal.backgroundColor = UIColor.black.cgColor
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = FadeRegion.duration
            fade.beginTime = region.start
            fade.fillMode = .backwards
            reveal.add(fade, forKey: "streaming")
            mask.addSublayer(reveal)
        }
        base.path = path
        base.fillRule = .evenOdd
        base.fillColor = UIColor.black.cgColor
        mask.addSublayer(base)
        self.mask = mask
        streamingMask = mask
        if let end = fadeRegions.map(\.end).max() {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, end - CACurrentMediaTime())) { [weak self, weak mask] in
                if let mask, self?.mask === mask { self?.clearStreamingMask() }
            }
        }
    }

    private func clearStreamingMask() {
        if let streamingMask, mask === streamingMask { mask = nil }
        streamingMask = nil
    }

    private func invalidateDisplay() {
        guardLock.lock()
        generation &+= 1
        guardLock.unlock()
        pendingBitmapTask = nil
    }

    private func currentGeneration() -> UInt {
        guardLock.lock()
        defer { guardLock.unlock() }
        return generation
    }

    func clearDisplayContents() {
        invalidateDisplay()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contents = nil
        stripTask = nil
        removeStrips()
        tiledLayer?.removeFromSuperlayer()
        tiledLayer = nil
        clearStreamingMask()
        CATransaction.commit()
        displayedSummary = nil
        fadeRegions.removeAll()
    }

    private static func renderImage(size: CGSize, scale: CGFloat, actions: (CGContext) -> Void) -> CGImage? {
        autoreleasepool {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            format.preferredRange = .standard
            return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                let context = renderer.cgContext
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                actions(context)
            }.cgImage
        }
    }
}
