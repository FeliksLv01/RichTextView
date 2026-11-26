import UIKit

@MainActor
protocol RichTextLoupeSession: AnyObject {
    func move(to point: CGPoint)
    func invalidate()
}

@available(iOS 17.0, *)
extension UITextLoupeSession: RichTextLoupeSession {
    func move(to point: CGPoint) {
        move(to: point, withCaretRect: .null, trackingCaret: false)
    }
}
