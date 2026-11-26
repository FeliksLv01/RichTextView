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
    public let interactiveRegions: [RichInteractiveRegion]
    public let lines: [RichLineBox]

    private let drawingBands: [IndexSet]
    private let bandHeight: CGFloat

    private static func band(at y: CGFloat, height: CGFloat, count: Int) -> Int {
        Int(min(CGFloat(count - 1), max(0, y / height)))
    }

    func drawingIndices(in rect: CGRect) -> IndexSet {
        guard !rect.isEmpty else { return [] }
        let first = Self.band(at: rect.minY, height: bandHeight, count: drawingBands.count)
        let last = Self.band(at: rect.maxY, height: bandHeight, count: drawingBands.count)
        var indices = drawingBands[first]
        for band in drawingBands[first...last].dropFirst() { indices.formUnion(band) }
        return indices
    }

    let codeBlockTextByID: [String: String]

    public convenience init(
        rootElementID: String,
        constrainedSize: CGSize,
        contentSize: CGSize,
        runBoxes: [RichRunBox],
        lines: [RichLineBox]
    ) {
        self.init(rootElementID: rootElementID, constrainedSize: constrainedSize, contentSize: contentSize,
                  runBoxes: runBoxes, lines: lines, codeBlockTextByID: [:])
    }

    init(
        rootElementID: String,
        constrainedSize: CGSize,
        contentSize: CGSize,
        runBoxes: [RichRunBox],
        lines: [RichLineBox],
        codeBlockTextByID: [String: String]
    ) {
        self.codeBlockTextByID = codeBlockTextByID
        self.rootElementID = rootElementID
        self.constrainedSize = constrainedSize
        self.contentSize = contentSize
        self.runBoxes = runBoxes
        // Bound the index size even for very tall or externally supplied layouts.
        let bandHeight = max(512, contentSize.height / 4096)
        self.bandHeight = bandHeight
        let bandCount = Int(min(4096, max(1, ceil(contentSize.height / bandHeight))))
        var bands = Array(repeating: IndexSet(), count: bandCount)
        for (index, box) in runBoxes.enumerated() where !box.frame.isNull {
            let first = Self.band(at: box.frame.minY, height: bandHeight, count: bandCount)
            let last = Self.band(at: box.frame.maxY, height: bandHeight, count: bandCount)
            for band in first...last { bands[band].insert(index) }
        }
        drawingBands = bands
        textRunBoxes = runBoxes.compactMap { $0 as? RichTextRunBox }
        imageRunBoxes = runBoxes.compactMap { $0 as? RichImageRunBox }
        attachmentRunBoxes = runBoxes.compactMap { $0 as? RichAttachmentRunBox }
        interactiveRegions = runBoxes.flatMap { box -> [RichInteractiveRegion] in
            if let text = box as? RichTextRunBox { return text.interactiveRegions }
            if let image = box as? RichImageRunBox, let action = image.element.action, !image.frame.isEmpty {
                return [RichInteractiveRegion(action: action, elementID: image.id, range: image.globalRange, rects: [image.frame])]
            }
            if let attachment = box as? RichAttachmentRunBox,
               let code = attachment.element.provider as? RichCodeBlockViewProvider,
               let region = code.copyRegion(in: attachment) {
                return [region]
            }
            return []
        }
        self.lines = lines
    }

    func interactiveRegion(at point: CGPoint) -> RichInteractiveRegion? {
        interactiveRegions.last { $0.contains(point) }
    }

    func textHit(at point: CGPoint) -> (runBox: RichTextRunBox, localPoint: CGPoint)? {
        guard let runBox = textRunBoxes.first(where: { $0.frame.insetBy(dx: -12, dy: -8).contains(point) }) else {
            return nil
        }
        return (runBox, CGPoint(x: point.x - runBox.frame.minX, y: point.y - runBox.frame.minY))
    }

    func listItemSelectionRange(at point: CGPoint) -> NSRange? {
        let marker = runBoxes.compactMap { $0 as? RichDecorationRunBox }.filter {
            guard case .listMarker = $0.decoration else { return false }
            return point.y >= $0.frame.minY && point.y < $0.frame.maxY
        }.min { $0.frame.height < $1.frame.height }
        guard let marker else { return nil }
        let ranges = runBoxes.compactMap { runBox -> NSRange? in
            guard runBox.frame.midY >= marker.frame.minY, runBox.frame.midY <= marker.frame.maxY else { return nil }
            if let text = runBox as? RichTextRunBox { return text.globalRange }
            if let image = runBox as? RichImageRunBox { return image.globalRange }
            if let attachment = runBox as? RichAttachmentRunBox { return attachment.globalRange }
            return nil
        }.filter { $0.length > 0 }
        guard let lower = ranges.map(\.location).min(),
              let upper = ranges.map(NSMaxRange).max() else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }
}
