import UIKit

struct RichSelectionCursor {
    enum Kind {
        case start
        case end
    }

    let kind: Kind
    let rect: CGRect
    let endpoint: CGPoint
    let hitTestInsets: UIEdgeInsets

    var hitTestRect: CGRect {
        rect.inset(by: hitTestInsets)
    }

    func contains(_ point: CGPoint) -> Bool {
        hitTestRect.contains(point)
    }

    func distance(to point: CGPoint) -> CGFloat {
        hypot(endpoint.x - point.x, endpoint.y - point.y)
    }
}

@MainActor
final class RichSelectionOverlayView: UIView {
    private static let handleEndpointOffset: CGFloat = 5.25
    private static let handleDiameter: CGFloat = 16.5
    private static let handleLineWidth: CGFloat = 2
    private static let handleMaximumStemHeight: CGFloat = 25.6667
    private static let cursorHitTestInsets = UIEdgeInsets(
        top: -30,
        left: -38,
        bottom: -30,
        right: -38
    )
    private let highlightLayer = CAShapeLayer()
    private let startStemLayer = CAShapeLayer()
    private let startDotLayer = CAShapeLayer()
    private let endStemLayer = CAShapeLayer()
    private let endDotLayer = CAShapeLayer()
    private var startCursor: RichSelectionCursor?
    private var endCursor: RichSelectionCursor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(highlightLayer)
        layer.addSublayer(startStemLayer)
        layer.addSublayer(startDotLayer)
        layer.addSublayer(endStemLayer)
        layer.addSublayer(endDotLayer)
        configureDotLayer(startDotLayer)
        configureDotLayer(endDotLayer)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(rects: [CGRect], startHandleRect: CGRect?, endHandleRect: CGRect?) {
        startCursor = makeCursor(kind: .start, selectionRect: startHandleRect)
        endCursor = makeCursor(kind: .end, selectionRect: endHandleRect)
        let path = UIBezierPath()
        rects.forEach { path.append(UIBezierPath(roundedRect: pixelAligned($0), cornerRadius: 1.5)) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.path = path.cgPath
        updateHandle(stemLayer: startStemLayer, dotLayer: startDotLayer, rect: startHandleRect, isStart: true)
        updateHandle(stemLayer: endStemLayer, dotLayer: endDotLayer, rect: endHandleRect, isStart: false)
        CATransaction.commit()
    }

    func cursor(at point: CGPoint) -> RichSelectionCursor? {
        [startCursor, endCursor]
            .compactMap { $0 }
            .filter { $0.contains(point) }
            .min { $0.distance(to: point) < $1.distance(to: point) }
    }

    func updateAppearance() {
        let tint = tintColor ?? UIColor(red: 48 / 255, green: 119 / 255, blue: 242 / 255, alpha: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.fillColor = tint.withAlphaComponent(0.2).cgColor
        startStemLayer.fillColor = tint.cgColor
        startDotLayer.fillColor = tint.cgColor
        endStemLayer.fillColor = tint.cgColor
        endDotLayer.fillColor = tint.cgColor
        CATransaction.commit()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateAppearance()
    }

    private func configureDotLayer(_ layer: CAShapeLayer) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    private func updateHandle(stemLayer: CAShapeLayer, dotLayer: CAShapeLayer, rect: CGRect?, isStart: Bool) {
        guard let rect else {
            stemLayer.path = nil
            dotLayer.path = nil
            dotLayer.shadowPath = nil
            return
        }
        let diameter = Self.handleDiameter
        let radius = diameter / 2
        let x = isStart ? rect.minX : rect.maxX
        let stemHeight = min(rect.height, Self.handleMaximumStemHeight)
        let stem = CGRect(
            x: x - Self.handleLineWidth / 2,
            y: isStart ? rect.minY : rect.maxY - stemHeight,
            width: Self.handleLineWidth,
            height: stemHeight
        )
        let dotCenterY = isStart
            ? rect.minY - Self.handleEndpointOffset
            : rect.maxY + Self.handleEndpointOffset
        let dotRect = CGRect(x: x - radius, y: dotCenterY - radius, width: diameter, height: diameter)
        stemLayer.path = UIBezierPath(roundedRect: stem, cornerRadius: 1).cgPath
        dotLayer.path = UIBezierPath(ovalIn: dotRect).cgPath
        dotLayer.shadowPath = UIBezierPath(ovalIn: dotRect).cgPath
    }

    private func makeCursor(
        kind: RichSelectionCursor.Kind,
        selectionRect: CGRect?
    ) -> RichSelectionCursor? {
        guard let selectionRect else { return nil }
        let isStart = kind == .start
        let x = isStart ? selectionRect.minX : selectionRect.maxX
        let stemHeight = min(selectionRect.height, Self.handleMaximumStemHeight)
        let stemRect = CGRect(
            x: x - Self.handleLineWidth / 2,
            y: isStart ? selectionRect.minY : selectionRect.maxY - stemHeight,
            width: Self.handleLineWidth,
            height: stemHeight
        )
        let endpoint = CGPoint(
            x: x,
            y: isStart
                ? selectionRect.minY - Self.handleEndpointOffset
                : selectionRect.maxY + Self.handleEndpointOffset
        )
        let radius = Self.handleDiameter / 2
        let dotRect = CGRect(
            x: endpoint.x - radius,
            y: endpoint.y - radius,
            width: Self.handleDiameter,
            height: Self.handleDiameter
        )
        return RichSelectionCursor(
            kind: kind,
            rect: stemRect.union(dotRect),
            endpoint: endpoint,
            hitTestInsets: Self.cursorHitTestInsets
        )
    }

    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let minX = floor(rect.minX * scale) / scale
        let minY = floor(rect.minY * scale) / scale
        let maxX = ceil(rect.maxX * scale) / scale
        let maxY = ceil(rect.maxY * scale) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
