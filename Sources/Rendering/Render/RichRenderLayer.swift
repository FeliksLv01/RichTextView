import UIKit

final class RichRenderLayerDisplayTask: @unchecked Sendable {
    var display: ((CGContext, CGSize, () -> Bool) -> Void)?
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

    override func setNeedsDisplay() {
        invalidateDisplay()
        super.setNeedsDisplay()
    }

    override func display() {
        let task = MainActor.assumeIsolated { richDisplayDelegate?.newRenderDisplayTask() }
        guard let task,
              let display = task.display,
              bounds.width > 0,
              bounds.height > 0 else {
            contents = nil
            return
        }
        let capturedGuard = currentGuardValue()
        let size = bounds.size
        let scale = max(1, contentsScale)
        if shouldUseTiles(size: size) {
            displayTiles(
                display: display,
                size: size,
                scale: scale,
                capturedGuard: capturedGuard,
                asynchronously: displaysAsynchronously
            )
            return
        }
        tiledLayerContainer?.removeFromSuperlayer()
        tiledLayerContainer = nil
        let renderImage = { [weak self] () -> CGImage? in
            guard let self else { return nil }
            let isCancelled = { [weak self] in
                self?.currentGuardValue() != capturedGuard
            }
            let image = Self.renderImage(size: size, scale: scale) { context in
                display(context, size, isCancelled)
            }
            guard !isCancelled() else { return nil }
            return image
        }
        if displaysAsynchronously {
            Self.displayQueue.async { [self] in
                let image = renderImage()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentGuardValue() == capturedGuard else { return }
                    self.contents = image
                }
            }
        } else {
            let image = renderImage()
            guard currentGuardValue() == capturedGuard else { return }
            contents = image
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

    private func shouldUseTiles(size: CGSize) -> Bool {
        maximumTileSize.width > 0
            && maximumTileSize.height > 0
            && (size.width > maximumTileSize.width || size.height > maximumTileSize.height)
    }

    private func displayTiles(
        display: @escaping (CGContext, CGSize, () -> Bool) -> Void,
        size: CGSize,
        scale: CGFloat,
        capturedGuard: UInt,
        asynchronously: Bool
    ) {
        contents = nil
        let container = tiledLayerContainer ?? CALayer()
        container.frame = bounds
        container.sublayers?.forEach { $0.removeFromSuperlayer() }
        if container.superlayer == nil { addSublayer(container) }
        tiledLayerContainer = container

        var tileRects: [CGRect] = []
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            let height = min(maximumTileSize.height, size.height - y)
            while x < size.width {
                let width = min(maximumTileSize.width, size.width - x)
                tileRects.append(CGRect(x: x, y: y, width: width, height: height))
                x += width
            }
            y += height
        }

        let renderTile = { [weak self] (tileRect: CGRect) -> CGImage? in
            guard let self else { return nil }
            let isCancelled = { [weak self] in
                self?.currentGuardValue() != capturedGuard
            }
            let image = Self.renderImage(size: tileRect.size, scale: scale) { context in
                let fullCanvasBottom = size.height - tileRect.maxY
                context.translateBy(x: -tileRect.minX, y: -fullCanvasBottom)
                display(context, size, isCancelled)
            }
            guard !isCancelled() else { return nil }
            return image
        }
        let installTile = { [weak self, weak container] (image: CGImage, tileRect: CGRect) in
            guard let self,
                  let container,
                  self.currentGuardValue() == capturedGuard,
                  self.tiledLayerContainer === container else { return }
            let tile = CALayer()
            tile.frame = tileRect
            tile.contentsScale = scale
            tile.contents = image
            container.addSublayer(tile)
        }

        for tileRect in tileRects {
            if asynchronously {
                Self.displayQueue.async {
                    guard let image = renderTile(tileRect) else { return }
                    DispatchQueue.main.async { installTile(image, tileRect) }
                }
            } else if let image = renderTile(tileRect) {
                installTile(image, tileRect)
            }
        }
    }
}
