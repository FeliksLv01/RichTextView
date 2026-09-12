import UIKit

public struct RichLineBox: Sendable {
    public let frame: CGRect
    public let runBoxIDs: [String]

    public init(frame: CGRect, runBoxIDs: [String]) {
        self.frame = frame
        self.runBoxIDs = runBoxIDs
    }
}

public final class RichTextLayout: Sendable {
    public let rootElementID: String
    public let constrainedSize: CGSize
    public let contentSize: CGSize
    public let runBoxes: [RichRunBox]
    public let textRunBoxes: [RichTextRunBox]
    public let imageRunBoxes: [RichImageRunBox]
    public let attachmentRunBoxes: [RichAttachmentRunBox]
    public let lines: [RichLineBox]

    public init(
        rootElementID: String,
        constrainedSize: CGSize,
        contentSize: CGSize,
        runBoxes: [RichRunBox],
        lines: [RichLineBox]
    ) {
        self.rootElementID = rootElementID
        self.constrainedSize = constrainedSize
        self.contentSize = contentSize
        self.runBoxes = runBoxes
        textRunBoxes = runBoxes.compactMap { $0 as? RichTextRunBox }
        imageRunBoxes = runBoxes.compactMap { $0 as? RichImageRunBox }
        attachmentRunBoxes = runBoxes.compactMap { $0 as? RichAttachmentRunBox }
        self.lines = lines
    }
}
