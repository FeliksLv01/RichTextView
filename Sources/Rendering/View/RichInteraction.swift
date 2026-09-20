import UIKit

public struct RichSemanticPosition: Hashable, Sendable {
    public let elementID: String
    public let utf16Offset: Int

    public init(elementID: String, utf16Offset: Int) {
        self.elementID = elementID
        self.utf16Offset = max(0, utf16Offset)
    }
}

public struct RichSemanticRange: Hashable, Sendable {
    public let start: RichSemanticPosition
    public let end: RichSemanticPosition

    public init(start: RichSemanticPosition, end: RichSemanticPosition) {
        self.start = start
        self.end = end
    }
}

public enum RichSelectionFragmentKind: Hashable, Sendable {
    case text
    case image
    case attachment
}

public struct RichSelectionFragment: Hashable, Sendable {
    public let elementID: String
    public let kind: RichSelectionFragmentKind
    public let utf16Range: NSRange
    public let globalRange: NSRange
    public let plainText: String

    public init(
        elementID: String,
        kind: RichSelectionFragmentKind,
        utf16Range: NSRange,
        globalRange: NSRange,
        plainText: String
    ) {
        self.elementID = elementID
        self.kind = kind
        self.utf16Range = utf16Range
        self.globalRange = globalRange
        self.plainText = plainText
    }
}

public struct RichSelection: Hashable, Sendable {
    public let globalRange: NSRange
    public let semanticRange: RichSemanticRange
    public let fragments: [RichSelectionFragment]
    public let plainText: String

    public init(
        globalRange: NSRange,
        semanticRange: RichSemanticRange,
        fragments: [RichSelectionFragment],
        plainText: String
    ) {
        self.globalRange = globalRange
        self.semanticRange = semanticRange
        self.fragments = fragments
        self.plainText = plainText
    }
}

public enum RichInitialSelectionPolicy: Sendable {
    case allContent
    case currentLine
    case paragraph
    case word
}

@MainActor
public struct RichSelectionMenuAction {
    public let title: String
    public let image: UIImage?
    public let perform: () -> Void

    public init(title: String, image: UIImage?, perform: @escaping () -> Void) {
        self.title = title
        self.image = image
        self.perform = perform
    }
}

@MainActor
public protocol RichSelectionMenuPresenting: AnyObject {
    func presentCopyMenu(
        from richView: RichTextView,
        sourceRect: CGRect,
        copy: @escaping () -> Void,
        selectionDidEnd: @escaping () -> Void
    )
    func presentSelectionMenu(
        from richView: RichTextView,
        sourceRect: CGRect,
        actions: [RichSelectionMenuAction],
        selectionDidEnd: @escaping () -> Void
    )
    func dismissCopyMenu(from richView: RichTextView)
}

public extension RichSelectionMenuPresenting {
    func presentSelectionMenu(
        from richView: RichTextView,
        sourceRect: CGRect,
        actions: [RichSelectionMenuAction],
        selectionDidEnd: @escaping () -> Void
    ) {
        guard let action = actions.first else {
            selectionDidEnd()
            return
        }
        presentCopyMenu(
            from: richView,
            sourceRect: sourceRect,
            copy: action.perform,
            selectionDidEnd: selectionDidEnd
        )
    }
}

@MainActor
public protocol RichTextViewInteractionDelegate: AnyObject {
    func richView(_ richView: RichTextView, didActivate actionIdentifier: String)
    func richViewDidTapUnconsumedContent(_ richView: RichTextView)
    func richView(_ richView: RichTextView, selectionDidChange selection: RichSelection?)
    func richView(_ richView: RichTextView, copy selection: RichSelection) -> Bool
    func richViewSelectionDidChange(_ richView: RichTextView, range: RichSemanticRange?)
    func richView(
        _ richView: RichTextView,
        copySelection range: RichSemanticRange,
        plainText: String
    ) -> Bool
}

public extension RichTextViewInteractionDelegate {
    func richView(_ richView: RichTextView, didActivate actionIdentifier: String) {}
    func richViewDidTapUnconsumedContent(_ richView: RichTextView) {}
    func richView(_ richView: RichTextView, selectionDidChange selection: RichSelection?) {
        richViewSelectionDidChange(richView, range: selection?.semanticRange)
    }
    func richView(_ richView: RichTextView, copy selection: RichSelection) -> Bool {
        self.richView(
            richView,
            copySelection: selection.semanticRange,
            plainText: selection.plainText
        )
    }
    func richViewSelectionDidChange(_ richView: RichTextView, range: RichSemanticRange?) {}
    func richView(
        _ richView: RichTextView,
        copySelection range: RichSemanticRange,
        plainText: String
    ) -> Bool { false }
}
