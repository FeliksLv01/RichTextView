import UIKit
import ObjectiveC

@MainActor
final class RichTextLoupeSession {
    private typealias BeginFunction = @convention(c) (
        AnyObject,
        Selector,
        CGPoint,
        UIView?,
        UIView
    ) -> AnyObject?
    private typealias MoveFunction = @convention(c) (
        AnyObject,
        Selector,
        CGPoint,
        CGRect,
        Bool
    ) -> Void
    private typealias InvalidateFunction = @convention(c) (AnyObject, Selector) -> Void

    private static let beginSelector = NSSelectorFromString(
        "beginLoupeSessionAtPoint:fromSelectionWidgetView:inView:"
    )
    private static let moveSelector = NSSelectorFromString(
        "moveToPoint:withCaretRect:trackingCaret:"
    )
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    private var session: NSObject?

    func begin(at point: CGPoint, in view: UIView) {
        invalidate()
        guard #available(iOS 17.0, *) else { return }
        guard let sessionType = NSClassFromString("UITextLoupeSession"),
              let method = class_getClassMethod(sessionType, Self.beginSelector) else { return }
        let function = unsafeBitCast(
            method_getImplementation(method),
            to: BeginFunction.self
        )
        guard let session = function(
            sessionType,
            Self.beginSelector,
            point,
            nil,
            view
        ) as? NSObject else { return }
        self.session = session
        move(to: point)
    }

    func move(to point: CGPoint) {
        guard let session,
              let method = class_getInstanceMethod(type(of: session), Self.moveSelector) else { return }
        let function = unsafeBitCast(
            method_getImplementation(method),
            to: MoveFunction.self
        )
        function(session, Self.moveSelector, point, .null, false)
    }

    func invalidate() {
        guard let session else { return }
        if let method = class_getInstanceMethod(type(of: session), Self.invalidateSelector) {
            let function = unsafeBitCast(
                method_getImplementation(method),
                to: InvalidateFunction.self
            )
            function(session, Self.invalidateSelector)
        }
        self.session = nil
    }
}
