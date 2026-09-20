import UIKit

final class RichRenderLayerDisplayTask: @unchecked Sendable {
    var display: ((CGContext, CGSize, () -> Bool) -> Void)?
    var animatesStreamingChanges = false
    var layout: RichTextLayout?
    var traits: UITraitCollection?
    var images: [String: UIImage] = [:]

    func appendedTextRects(comparedTo previous: RichRenderLayerDisplayTask?) -> [CGRect]? {
        guard let layout, let old = previous?.layout, traits == previous?.traits,
              layout.rootElementID == old.rootElementID,
              layout.constrainedSize.width == old.constrainedSize.width else { return nil }
        let oldRuns = Dictionary(uniqueKeysWithValues: old.textRunBoxes.map { ($0.id, $0) })
        let newIDs = Set(layout.textRunBoxes.map(\.id))
        guard oldRuns.keys.allSatisfy({ newIDs.contains($0) }) else { return nil }
        var rects: [CGRect] = []
        for run in layout.textRunBoxes {
            let count = oldRuns[run.id]?.text.length ?? 0
            if let oldRun = oldRuns[run.id] {
                if run.hasSameDrawing(as: oldRun) { continue }
                guard run.frame.origin == oldRun.frame.origin, run.text.length >= count,
                      run.text.attributedSubstring(from: NSRange(location: 0, length: count)) == oldRun.text,
                      run.layout.selectionRects(for: NSRange(location: 0, length: count))
                        == oldRun.layout.selectionRects(for: NSRange(location: 0, length: count)) else { return nil }
            }
            guard run.text.length > count else { continue }
            let string = run.text.string
            let range = NSRange(location: count, length: run.text.length - count)
            guard let swiftRange = Range(range, in: string) else { continue }
            var cursor = count
            string.enumerateSubstrings(in: swiftRange, options: [.byWords, .substringNotRequired]) { _, word, _, _ in
                let end = NSMaxRange(NSRange(word, in: string))
                rects += run.layout.selectionRects(for: NSRange(location: cursor, length: end - cursor))
                    .map { $0.offsetBy(dx: run.frame.minX, dy: run.frame.minY) }
                cursor = end
            }
            if cursor < run.text.length {
                rects += run.layout.selectionRects(for: NSRange(location: cursor, length: run.text.length - cursor))
                    .map { $0.offsetBy(dx: run.frame.minX, dy: run.frame.minY) }
            }
        }
        return rects
    }

    func unchangedPrefixHeight(comparedTo previous: RichRenderLayerDisplayTask?) -> CGFloat {
        guard let previous, traits == previous.traits, images == previous.images,
              let layout, let old = previous.layout,
              layout.rootElementID == old.rootElementID,
              layout.constrainedSize.width == old.constrainedSize.width else { return 0 }
        let runs = layout.runBoxes
        let oldRuns = old.runBoxes
        var index = 0
        while index < min(runs.count, oldRuns.count), runs[index].hasSameDrawing(as: oldRuns[index]) {
            index += 1
        }
        // Decorations can precede their children and overlap them; include the entire changed suffix.
        return (runs.dropFirst(index) + oldRuns.dropFirst(index)).map(\.frame.minY).min() ?? .greatestFiniteMagnitude
    }
}

@MainActor
protocol RichRenderLayerDelegate: AnyObject {
    func newRenderDisplayTask() -> RichRenderLayerDisplayTask
}

final class RichRenderLayer: CALayer {
    weak var richDisplayDelegate: RichRenderLayerDelegate?
    var displaysAsynchronously = false
    var maximumTileSize = CGSize(width: 1_024, height: 1_024)

    private static let displayQueue = DispatchQueue(
        label: "io.github.felikslv01.rich-text-view.display",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let guardLock = NSLock()
    private var guardValue: UInt = 0
    private var tiledLayerContainer: CALayer?
    private var displayedTask: RichRenderLayerDisplayTask?
    private var displayedScale: CGFloat = 0
    private var fadeRegions: [(rect: CGRect, start: CFTimeInterval)] = []
    private let fadeDuration: CFTimeInterval = 0.25

    override func setNeedsDisplay() {
        invalidateDisplay()
        super.setNeedsDisplay()
    }

    override func display() {
        let task = MainActor.assumeIsolated { richDisplayDelegate?.newRenderDisplayTask() }
        guard let task, let display = task.display,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            clearDisplayContents()
            return
        }
        let capturedGuard = currentGuardValue()
        let size = bounds.size
        let scale = max(1, contentsScale)
        let prefix = displayedScale == scale ? task.unchangedPrefixHeight(comparedTo: displayedTask) : 0
        let oldTiles = tiledLayerContainer?.sublayers ?? []
        let tileWidth = maximumTileSize.width > 0 ? min(size.width, maximumTileSize.width) : size.width
        let tileHeight = maximumTileSize.height > 0 ? min(size.height, maximumTileSize.height) : size.height
        var rects: [CGRect] = []
        var reused: [Int: CALayer] = [:]
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let rect = CGRect(x: x, y: y, width: min(tileWidth, size.width - x), height: min(tileHeight, size.height - y))
                let index = rects.count
                if rect.maxY <= prefix, index < oldTiles.count, oldTiles[index].frame == rect {
                    reused[index] = oldTiles[index]
                }
                rects.append(rect)
                x += tileWidth
            }
            y += tileHeight
        }
        let render = { [weak self] () -> [Int: CGImage] in
            var images: [Int: CGImage] = [:]
            let isCancelled = { [weak self] in self?.currentGuardValue() != capturedGuard }
            for (index, rect) in rects.enumerated() where reused[index] == nil {
                guard !isCancelled() else { return [:] }
                images[index] = Self.renderImage(size: rect.size, scale: scale) { context in
                    context.translateBy(x: -rect.minX, y: -(size.height - rect.maxY))
                    display(context, size, isCancelled)
                }
            }
            return images
        }
        let install = { [weak self] (images: [Int: CGImage]) in
            guard let self, self.currentGuardValue() == capturedGuard else { return }
            // Commit one complete generation. Keep the old pixels until all changed tiles are ready.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let now = CACurrentMediaTime()
            if task.animatesStreamingChanges, let appended = task.appendedTextRects(comparedTo: self.displayedTask) {
                self.fadeRegions.removeAll { now - $0.start >= self.fadeDuration }
                for (index, rect) in appended.enumerated() {
                    self.fadeRegions.append((rect, now + 0.1 * Double(index) / Double(max(1, appended.count))))
                }
            } else {
                self.fadeRegions.removeAll()
            }
            let container = self.tiledLayerContainer ?? CALayer()
            var tiles: [CALayer] = []
            container.frame = CGRect(origin: .zero, size: size)
            for (index, rect) in rects.enumerated() {
                let tile = reused[index] ?? CALayer()
                tile.frame = rect
                tile.contentsScale = scale
                if let image = images[index] { tile.contents = image }
                self.applyFadeMask(to: tile)
                tiles.append(tile)
            }
            container.sublayers = tiles
            if container.superlayer == nil { self.insertSublayer(container, at: 0) }
            self.tiledLayerContainer = container
            self.contents = nil
            self.displayedTask = task
            self.displayedScale = scale
            CATransaction.commit()
        }
        if displaysAsynchronously {
            Self.displayQueue.async {
                let images = render()
                DispatchQueue.main.async { install(images) }
            }
        } else {
            install(render())
        }
    }

    func invalidateDisplay() {
        guardLock.lock()
        guardValue &+= 1
        guardLock.unlock()
    }

    func clearDisplayContents() {
        invalidateDisplay()
        contents = nil
        tiledLayerContainer?.removeFromSuperlayer()
        tiledLayerContainer = nil
        displayedTask = nil
        fadeRegions.removeAll()
    }

    private func applyFadeMask(to tile: CALayer) {
        let regions = fadeRegions.filter { $0.rect.intersects(tile.frame) }
        guard !regions.isEmpty else { tile.mask = nil; return }
        let mask = CALayer()
        mask.frame = tile.bounds
        let base = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(tile.bounds)
        for region in regions {
            let rect = region.rect.intersection(tile.frame).offsetBy(dx: -tile.frame.minX, dy: -tile.frame.minY)
            path.addRect(rect)
            let reveal = CALayer()
            reveal.frame = rect
            reveal.backgroundColor = UIColor.black.cgColor
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = fadeDuration
            fade.beginTime = region.start
            fade.fillMode = .backwards
            reveal.add(fade, forKey: "streaming")
            mask.addSublayer(reveal)
        }
        base.path = path
        base.fillRule = .evenOdd
        base.fillColor = UIColor.black.cgColor
        mask.addSublayer(base)
        tile.mask = mask
    }

    private func currentGuardValue() -> UInt {
        guardLock.lock()
        defer { guardLock.unlock() }
        return guardValue
    }

    private static func renderImage(
        size: CGSize,
        scale: CGFloat,
        actions: (CGContext) -> Void
    ) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { rendererContext in
            let context = rendererContext.cgContext
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            actions(context)
        }.cgImage
    }

}
