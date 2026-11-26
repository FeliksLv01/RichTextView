import UIKit

final class RichSelectionHighlightView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isUserInteractionEnabled = false
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(rects: [CGRect]) {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let path = UIBezierPath()
        for rect in rects {
            let pixels = rect.applying(CGAffineTransform(scaleX: scale, y: scale)).integral
            let aligned = pixels.applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
            path.append(UIBezierPath(roundedRect: aligned, cornerRadius: 1.5))
        }
        (layer as? CAShapeLayer)?.path = path.cgPath
    }

    func updateAppearance() {
        (layer as? CAShapeLayer)?.fillColor = tintColor.withAlphaComponent(0.2).cgColor
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateAppearance()
    }
}

enum RichSelectionHandleKind { case start, end }

final class RichSelectionHandleView: UIView {
    let kind: RichSelectionHandleKind
    private static let diameter: CGFloat = 16.5
    private static let endpointOffset: CGFloat = 5.25
    private lazy var dotLayer: CALayer = {
        let dot = CALayer()
        dot.cornerRadius = Self.diameter / 2
        dot.shadowColor = UIColor.black.cgColor
        dot.shadowOpacity = 0.3
        dot.shadowRadius = 8
        dot.shadowOffset = CGSize(width: 0, height: 2)
        return dot
    }()
    private lazy var stemLayer: CALayer = {
        let stem = CALayer()
        stem.cornerRadius = 1
        return stem
    }()

    init(kind: RichSelectionHandleKind, target: AnyObject, action: Selector) {
        self.kind = kind
        super.init(frame: .zero)
        let pan = UIPanGestureRecognizer(target: target, action: action)
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        layer.addSublayer(stemLayer)
        layer.addSublayer(dotLayer)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func position(at rect: CGRect) {
        let isStart = kind == .start
        let x = isStart ? rect.minX : rect.maxX
        let y = isStart ? rect.minY : rect.maxY
        let height = min(rect.height, 25.6667)
        let stem = CGRect(x: x - 1, y: isStart ? y : y - height, width: 2, height: height)
        let radius = Self.diameter / 2
        let centerY = y + (isStart ? -Self.endpointOffset : Self.endpointOffset)
        let dot = CGRect(x: x - radius, y: centerY - radius, width: Self.diameter, height: Self.diameter)
        let newFrame = dot.union(stem)
        guard frame != newFrame else { return }
        frame = newFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stemLayer.frame = stem.offsetBy(dx: -frame.minX, dy: -frame.minY)
        dotLayer.frame = dot.offsetBy(dx: -frame.minX, dy: -frame.minY)
        CATransaction.commit()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -38, dy: -30).contains(point)
    }

    func distanceToEndpoint(from point: CGPoint) -> CGFloat {
        hypot(point.x - dotLayer.position.x, point.y - dotLayer.position.y)
    }

    private func updateAppearance() {
        dotLayer.backgroundColor = tintColor.cgColor
        stemLayer.backgroundColor = tintColor.cgColor
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateAppearance()
    }
}

final class RichSelectionHandleOverlay: UIView {
    private let startHandle: RichSelectionHandleView
    private let endHandle: RichSelectionHandleView

    init(target: AnyObject, action: Selector) {
        startHandle = RichSelectionHandleView(kind: .start, target: target, action: action)
        endHandle = RichSelectionHandleView(kind: .end, target: target, action: action)
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(startHandle)
        addSubview(endHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func position(start: CGRect, end: CGRect) {
        startHandle.position(at: start)
        endHandle.position(at: end)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        // Short selections have overlapping hit areas. Prefer the nearest dot.
        var nearest: RichSelectionHandleView?
        var distance = CGFloat.infinity
        for handle in [startHandle, endHandle] where bounds.intersects(handle.frame) {
            let local = convert(point, to: handle)
            guard handle.point(inside: local, with: event) else { continue }
            let candidate = handle.distanceToEndpoint(from: local)
            if candidate < distance {
                nearest = handle
                distance = candidate
            }
        }
        return nearest
    }
}

@MainActor
enum RichSelectionWindowCoordinator {
    private static let owners = NSMapTable<UIWindow, RichSelectionController>.weakToWeakObjects()

    static func claim(_ window: UIWindow, for controller: RichSelectionController) {
        let previous = owners.object(forKey: window)
        owners.setObject(controller, forKey: window)
        if previous !== controller { previous?.clearSelection() }
    }

    static func release(_ window: UIWindow, for controller: RichSelectionController) {
        if owners.object(forKey: window) === controller { owners.removeObject(forKey: window) }
    }
}
