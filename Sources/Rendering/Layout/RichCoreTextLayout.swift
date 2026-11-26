@preconcurrency import CoreText
import UIKit

final class RichCoreTextLayout: @unchecked Sendable {
    struct LineFragment: Sendable {
        let range: NSRange
        let frame: CGRect
        let coreTextOrigin: CGPoint
        let stringIndexOffset: Int
    }

    let attributedText: NSAttributedString
    let drawingID = UUID()
    let size: CGSize
    let lines: [LineFragment]

    private let constrainedWidth: CGFloat
    private let maximumNumberOfLines: Int
    private let lineBreakMode: NSLineBreakMode
    private let originThreadID = UInt(bitPattern: pthread_self())
    private let originLines: [CTLine]
    private let lock = NSLock()
    private var secondaryLines: (threadID: UInt, lines: [CTLine])?

    private typealias DrawingLine = (fragment: LineFragment, line: CTLine)

    // 可见高度取截断前的行度量，实际绘制与命中测试使用截断后的行。
    private struct TypesetLines {
        let ordered: [(line: CTLine, origin: CGPoint)]
        let truncatedLastLine: CTLine?
        let frameHeight: CGFloat
        let suggestedWidth: CGFloat

        var visibleLines: [CTLine] {
            var lines = ordered.map(\.line)
            if let truncatedLastLine { lines[lines.count - 1] = truncatedLastLine }
            return lines
        }
    }

    init?(
        attributedText: NSAttributedString,
        constrainedWidth: CGFloat,
        maximumNumberOfLines: Int = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) {
        guard attributedText.length > 0, constrainedWidth > 0 else { return nil }
        self.attributedText = attributedText.copy() as! NSAttributedString
        self.constrainedWidth = constrainedWidth
        self.maximumNumberOfLines = maximumNumberOfLines
        self.lineBreakMode = lineBreakMode
        let width = Self.layoutWidth(constrainedWidth, lineBreakMode)
        let typeset = Self.typeset(
            self.attributedText, width: width,
            maximumNumberOfLines: maximumNumberOfLines, lineBreakMode: lineBreakMode
        )
        let visibleLines = typeset.visibleLines
        originLines = visibleLines

        let visibleHeight = ceil(typeset.ordered.map { raw in
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(raw.line, nil, &descent, &leading)
            return typeset.frameHeight - raw.origin.y + descent + leading
        }.max() ?? 0)
        lines = typeset.ordered.enumerated().map { index, raw in
            let line = visibleLines[index]
            let originalRange = CTLineGetStringRange(raw.line)
            let sourceRange = NSRange(location: originalRange.location, length: originalRange.length)
            let isTruncated = index == visibleLines.count - 1 && typeset.truncatedLastLine != nil
            let range = isTruncated
                ? Self.visibleSourceRange(in: line, sourceOffset: sourceRange.location, fallback: sourceRange)
                : sourceRange
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let y = max(0, typeset.frameHeight - raw.origin.y - ascent)
            return LineFragment(
                range: range,
                frame: CGRect(x: raw.origin.x, y: y, width: ceil(min(width, lineWidth)), height: ascent + descent + leading),
                coreTextOrigin: CGPoint(x: raw.origin.x, y: visibleHeight - y - ascent),
                stringIndexOffset: isTruncated ? sourceRange.location : 0
            )
        }
        let measuredWidth = lines.map(\.frame.maxX).max() ?? typeset.suggestedWidth
        size = CGSize(width: min(width, ceil(measuredWidth)), height: visibleHeight)
    }

    func linesForCurrentThread() -> [CTLine] {
        let threadID = UInt(bitPattern: pthread_self())
        if threadID == originThreadID { return originLines }
        if let cached = lock.withLock({ secondaryLines?.threadID == threadID ? secondaryLines?.lines : nil }) {
            return cached
        }

        let lines = Self.typeset(
            attributedText, width: Self.layoutWidth(constrainedWidth, lineBreakMode),
            maximumNumberOfLines: maximumNumberOfLines, lineBreakMode: lineBreakMode
        ).visibleLines
        lock.withLock { secondaryLines = (threadID, lines) }
        return lines
    }

    private static func layoutWidth(_ constrainedWidth: CGFloat, _ lineBreakMode: NSLineBreakMode) -> CGFloat {
        // 不折行模式保留实际内容宽度，供外层横向滚动。
        lineBreakMode == .byClipping ? 100_000 : min(100_000, constrainedWidth)
    }

    private static func typeset(
        _ attributedText: NSAttributedString,
        width: CGFloat,
        maximumNumberOfLines: Int,
        lineBreakMode: NSLineBreakMode
    ) -> TypesetLines {
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(width: width, height: 100_000),
            nil
        )
        let fullHeight = max(1, ceil(suggested.height))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: fullHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            path,
            nil
        )
        let allLines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = Array(repeating: CGPoint.zero, count: allLines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let lineLimit = maximumNumberOfLines > 0 ? min(maximumNumberOfLines, allLines.count) : allLines.count
        let orderedLines = zip(allLines, origins).sorted { first, second in
            if first.1.y == second.1.y {
                return CTLineGetStringRange(first.0).location < CTLineGetStringRange(second.0).location
            }
            return first.1.y > second.1.y
        }
        let ordered: [(line: CTLine, origin: CGPoint)] = Array(orderedLines.prefix(lineLimit))
        var truncatedLastLine: CTLine?
        if allLines.count > lineLimit, let last = ordered.last, let type = truncationType(for: lineBreakMode) {
            let start = CTLineGetStringRange(last.line).location
            let remaining = attributedText.attributedSubstring(from: NSRange(location: start, length: attributedText.length - start))
            let candidate = CTLineCreateWithAttributedString(remaining)
            let token = truncationToken(for: attributedText, location: start)
            truncatedLastLine = CTLineCreateTruncatedLine(candidate, Double(width), type, token)
        }
        return TypesetLines(ordered: ordered, truncatedLastLine: truncatedLastLine, frameHeight: fullHeight, suggestedWidth: suggested.width)
    }

    func draw(
        in context: CGContext,
        canvasHeight: CGFloat,
        origin: CGPoint,
        imageResolver: ((String) -> UIImage?)? = nil,
        isCancelled: () -> Bool
    ) {
        guard !isCancelled() else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: origin.x, y: canvasHeight - origin.y - size.height)
        context.clip(to: CGRect(origin: .zero, size: size))
        let clip = context.boundingBoxOfClipPath
        let visibleRect = CGRect(x: clip.minX, y: size.height - clip.maxY, width: clip.width, height: clip.height)
        let visibleLines = zip(lines, linesForCurrentThread()).filter { $0.0.frame.intersects(visibleRect) }
        drawRunBackgrounds(in: context, lines: visibleLines, isCancelled: isCancelled)
        for (line, ctLine) in visibleLines {
            guard !isCancelled() else { break }
            context.textPosition = line.coreTextOrigin
            CTLineDraw(ctLine, context)
        }
        drawLatex(in: context, lines: visibleLines, isCancelled: isCancelled)
        drawInlineTextBadges(in: context, lines: visibleLines, isCancelled: isCancelled)
        drawInlineImages(in: context, lines: visibleLines, imageResolver: imageResolver, isCancelled: isCancelled)
        context.restoreGState()
    }

    func characterRange(at point: CGPoint) -> NSRange? {
        guard let position = closestPosition(to: point) else { return nil }
        let string = attributedText.string as NSString
        guard string.length > 0 else { return nil }
        let index = min(max(0, position), string.length - 1)
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        if let scalar = UnicodeScalar(string.character(at: index)), separators.contains(scalar) {
            return string.rangeOfComposedCharacterSequence(at: index)
        }
        var lower = index
        var upper = index + 1
        while lower > 0,
              let scalar = UnicodeScalar(string.character(at: lower - 1)),
              !separators.contains(scalar) {
            lower -= 1
        }
        while upper < string.length,
              let scalar = UnicodeScalar(string.character(at: upper)),
              !separators.contains(scalar) {
            upper += 1
        }
        return NSRange(location: lower, length: max(1, upper - lower))
    }

    func closestPosition(to point: CGPoint) -> Int? {
        guard let index = closestLineIndex(to: point) else { return nil }
        let line = lines[index]
        let relative = CGPoint(x: max(0, point.x - line.frame.minX), y: 0)
        let position = CTLineGetStringIndexForPosition(linesForCurrentThread()[index], relative)
        guard position != kCFNotFound else { return NSMaxRange(line.range) }
        let sourceIndex = line.stringIndexOffset + position
        return min(NSMaxRange(line.range), max(line.range.location, sourceIndex))
    }

    func lineRange(at point: CGPoint) -> NSRange? {
        closestLineIndex(to: point).map { lines[$0].range }
    }

    func paragraphRange(at point: CGPoint) -> NSRange? {
        guard let lineRange = lineRange(at: point),
              let position = closestPosition(to: point) else { return nil }
        let string = attributedText.string as NSString
        guard string.length > 0 else { return nil }
        let index = min(max(lineRange.location, position), NSMaxRange(lineRange) - 1)
        var range = string.paragraphRange(for: NSRange(location: index, length: 0))
        while range.length > 0,
              let scalar = UnicodeScalar(string.character(at: NSMaxRange(range) - 1)),
              CharacterSet.newlines.contains(scalar) {
            range.length -= 1
        }
        return range.length > 0 ? range : lineRange
    }

    /// ICU 按词切分（与系统文本选择一致，中文为词粒度而非标点间整句）；
    /// 点位不在任何词上时回落到该处的 composed character。
    func wordRange(at point: CGPoint) -> NSRange? {
        guard let lineRange = lineRange(at: point),
              let position = closestPosition(to: point) else { return nil }
        let string = attributedText.string as NSString
        guard string.length > 0 else { return nil }
        let index = min(max(lineRange.location, position), NSMaxRange(lineRange) - 1)
        guard index >= 0, index < string.length else { return nil }
        var match: NSRange?
        string.enumerateSubstrings(
            in: lineRange,
            options: [.byWords, .substringNotRequired]
        ) { _, wordRange, _, stop in
            if NSLocationInRange(index, wordRange) {
                match = wordRange
                stop.pointee = true
            } else if wordRange.location > index {
                stop.pointee = true
            }
        }
        return match ?? string.rangeOfComposedCharacterSequence(at: index)
    }

    func selectionRects(for range: NSRange) -> [CGRect] {
        zip(lines, linesForCurrentThread()).compactMap { line, ctLine in
            let intersection = NSIntersectionRange(range, line.range)
            guard intersection.length > 0 else { return nil }
            let start = CGFloat(CTLineGetOffsetForStringIndex(
                ctLine,
                intersection.location - line.stringIndexOffset,
                nil
            ))
            let end = CGFloat(CTLineGetOffsetForStringIndex(
                ctLine,
                NSMaxRange(intersection) - line.stringIndexOffset,
                nil
            ))
            return CGRect(
                x: line.frame.minX + min(start, end),
                y: line.frame.minY,
                width: max(1, abs(end - start)),
                height: max(1, line.frame.height)
            )
        }
    }

    /// A logical range can occupy disjoint visual runs in bidirectional or truncated text.
    func interactiveRects(for range: NSRange) -> [CGRect] {
        var rects: [CGRect] = []
        for (line, ctLine) in zip(lines, linesForCurrentThread()) where NSIntersectionRange(line.range, range).length > 0 {
            let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
            let spans = runs.compactMap { run -> CGRect? in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard attributes[RichCoreTextAttribute.truncationToken] == nil else { return nil }
                let indices = CTRunGetStringRange(run)
                let source = NSRange(location: indices.location + line.stringIndexOffset, length: indices.length)
                let overlap = NSIntersectionRange(source, range)
                guard overlap.length > 0, CTRunGetGlyphCount(run) > 0 else { return nil }

                var position = CGPoint.zero
                CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
                let left = position.x
                let right = left + CGFloat(CTRunGetTypographicBounds(run, CFRange(), nil, nil, nil))
                guard right > left else { return nil }
                let isRTL = CTRunGetStatus(run).contains(.rightToLeft)
                func offset(at index: Int) -> CGFloat {
                    if index == source.location { return isRTL ? right : left }
                    if index == NSMaxRange(source) { return isRTL ? left : right }
                    var secondary: CGFloat = 0
                    let primary = CTLineGetOffsetForStringIndex(ctLine, index - line.stringIndexOffset, &secondary)
                    return (left...right).contains(primary) ? primary : min(right, max(left, secondary))
                }

                let start = offset(at: overlap.location)
                let end = offset(at: NSMaxRange(overlap))
                let rect = CGRect(x: line.frame.minX + min(start, end), y: line.frame.minY,
                                  width: abs(end - start), height: line.frame.height)
                    .intersection(CGRect(origin: .zero, size: size))
                return rect.isEmpty ? nil : rect
            }.sorted { $0.minX < $1.minX }

            var merged: CGRect?
            for span in spans {
                if let previous = merged, span.minX <= previous.maxX + 0.001 {
                    merged = previous.union(span)
                } else {
                    if let merged { rects.append(merged) }
                    merged = span
                }
            }
            if let merged { rects.append(merged) }
        }
        return rects
    }

    func inlineRunRect(at location: Int) -> CGRect? {
        for (line, ctLine) in zip(lines, linesForCurrentThread()) where NSLocationInRange(location, line.range) {
            let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
            for run in runs {
                let runRange = CTRunGetStringRange(run)
                let sourceRange = NSRange(
                    location: line.stringIndexOffset + runRange.location,
                    length: runRange.length
                )
                guard NSLocationInRange(location, sourceRange) else {
                    continue
                }
                var lineAscent: CGFloat = 0
                var lineDescent: CGFloat = 0
                var lineLeading: CGFloat = 0
                CTLineGetTypographicBounds(
                    ctLine,
                    &lineAscent,
                    &lineDescent,
                    &lineLeading
                )
                var runAscent: CGFloat = 0
                var runDescent: CGFloat = 0
                let width = CGFloat(CTRunGetTypographicBounds(
                    run,
                    CFRange(location: 0, length: 0),
                    &runAscent,
                    &runDescent,
                    nil
                ))
                let x = line.frame.minX + CGFloat(
                    CTLineGetOffsetForStringIndex(
                        ctLine,
                        runRange.location,
                        nil
                    )
                )
                return CGRect(
                    x: x,
                    y: line.frame.minY + lineAscent - runAscent,
                    width: width,
                    height: runAscent + runDescent
                )
            }
        }
        return nil
    }

    private func closestLineIndex(to point: CGPoint) -> Int? {
        if let contained = lines.firstIndex(where: { $0.frame.insetBy(dx: 0, dy: -4).contains(point) }) {
            return contained
        }
        return lines.indices.min { abs(lines[$0].frame.midY - point.y) < abs(lines[$1].frame.midY - point.y) }
    }

    private static func truncationType(for lineBreakMode: NSLineBreakMode) -> CTLineTruncationType? {
        switch lineBreakMode {
        case .byTruncatingHead: .start
        case .byTruncatingMiddle: .middle
        case .byTruncatingTail: .end
        default: nil
        }
    }

    private static func truncationToken(for text: NSAttributedString, location: Int) -> CTLine {
        let safeLocation = min(max(0, location), max(0, text.length - 1))
        var attributes = text.attributes(at: safeLocation, effectiveRange: nil)
        attributes[RichCoreTextAttribute.truncationToken] = true
        return CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
    }

    private static func visibleSourceRange(
        in line: CTLine,
        sourceOffset: Int,
        fallback: NSRange
    ) -> NSRange {
        let ranges = (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).compactMap { run -> NSRange? in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard attributes[RichCoreTextAttribute.truncationToken] == nil else { return nil }
            let range = CTRunGetStringRange(run)
            guard range.location != kCFNotFound, range.length > 0 else { return nil }
            return NSRange(location: sourceOffset + range.location, length: range.length)
        }
        guard let lowerBound = ranges.map(\.location).min(),
              let upperBound = ranges.map(NSMaxRange).max(),
              upperBound > lowerBound else { return fallback }
        return NSRange(location: lowerBound, length: upperBound - lowerBound)
    }

    private func drawInlineImages(
        in context: CGContext,
        lines: [DrawingLine],
        imageResolver: ((String) -> UIImage?)?,
        isCancelled: () -> Bool
    ) {
        for (line, ctLine) in lines {
            guard !isCancelled() else { return }
            let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
            for run in runs {
                guard let attachment = (CTRunGetAttributes(run) as NSDictionary)[RichCoreTextAttribute.inlineImage]
                    as? RichInlineImageAttachment,
                    let image = (imageResolver?(attachment.identifier) ?? attachment.image)?.cgImage else { continue }
                let runRange = CTRunGetStringRange(run)
                let x = line.coreTextOrigin.x
                    + CGFloat(CTLineGetOffsetForStringIndex(ctLine, runRange.location, nil))
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                let width = CGFloat(CTRunGetTypographicBounds(
                    run,
                    CFRange(location: 0, length: 0),
                    &ascent,
                    &descent,
                    nil
                ))
                let rect = CGRect(
                    x: x,
                    y: line.coreTextOrigin.y - descent,
                    width: width,
                    height: ascent + descent
                )
                RichImageDrawing.draw(
                    image,
                    in: RichImageDrawing.fittedRect(
                        imageSize: CGSize(width: image.width, height: image.height),
                        in: rect,
                        contentInsets: attachment.contentInsets,
                        contentMode: attachment.contentMode
                    ),
                    tintColor: attachment.tintColor,
                    context: context
                )
            }
        }
    }

    private func drawLatex(in context: CGContext, lines: [DrawingLine], isCancelled: () -> Bool) {
        for (line, ctLine) in lines {
            guard !isCancelled() else { return }
            for run in CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? [] {
                guard let latex = (CTRunGetAttributes(run) as NSDictionary)[RichLatexRun.attribute] as? RichLatexRun else { continue }
                let range = CTRunGetStringRange(run)
                let x = line.coreTextOrigin.x + CGFloat(CTLineGetOffsetForStringIndex(ctLine, range.location, nil))
                let rect = CGRect(x: x, y: line.coreTextOrigin.y - latex.descent, width: latex.width, height: latex.ascent + latex.descent)
                guard rect.intersects(context.boundingBoxOfClipPath) else { continue }
                latex.draw(in: context, baseline: CGPoint(x: x, y: line.coreTextOrigin.y))
            }
        }
    }

    private func drawInlineTextBadges(in context: CGContext, lines: [DrawingLine], isCancelled: () -> Bool) {
        for (line, ctLine) in lines {
            guard !isCancelled() else { return }
            let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
            for run in runs {
                guard let badge = (CTRunGetAttributes(run) as NSDictionary)[RichCoreTextAttribute.inlineTextBadge]
                    as? RichInlineTextBadge else { continue }
                let runRange = CTRunGetStringRange(run)
                let x = line.coreTextOrigin.x
                    + CGFloat(CTLineGetOffsetForStringIndex(ctLine, runRange.location, nil))
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                let width = CGFloat(CTRunGetTypographicBounds(
                    run,
                    CFRange(location: 0, length: 0),
                    &ascent,
                    &descent,
                    nil
                ))
                let rect = CGRect(
                    x: x,
                    y: line.coreTextOrigin.y - descent,
                    width: width,
                    height: ascent + descent
                )
                let badgeRect = CGRect(
                    x: rect.minX + badge.outerInsets.left,
                    y: rect.minY + badge.outerInsets.bottom,
                    width: max(0, rect.width - badge.outerInsets.left - badge.outerInsets.right),
                    height: max(0, rect.height - badge.outerInsets.top - badge.outerInsets.bottom)
                )
                context.setFillColor(badge.backgroundColor.cgColor)
                context.addPath(CGPath(
                    roundedRect: badgeRect,
                    cornerWidth: min(badge.cornerRadius, badgeRect.height / 2),
                    cornerHeight: min(badge.cornerRadius, badgeRect.height / 2),
                    transform: nil
                ))
                context.fillPath()
                if let borderColor = badge.borderColor, badge.borderWidth > 0 {
                    context.setStrokeColor(borderColor.cgColor)
                    context.setLineWidth(badge.borderWidth)
                    context.addPath(CGPath(
                        roundedRect: badgeRect.insetBy(dx: badge.borderWidth / 2, dy: badge.borderWidth / 2),
                        cornerWidth: min(badge.cornerRadius, badgeRect.height / 2),
                        cornerHeight: min(badge.cornerRadius, badgeRect.height / 2),
                        transform: nil
                    ))
                    context.strokePath()
                }
                context.textPosition = CGPoint(
                    x: badgeRect.minX + badge.contentInsets.left,
                    y: badgeRect.minY + badge.contentInsets.bottom + badge.textDescent
                )
                CTLineDraw(badge.lineForCurrentThread(), context)
            }
        }
    }

    private func drawRunBackgrounds(in context: CGContext, lines: [DrawingLine], isCancelled: () -> Bool) {
        for (line, ctLine) in lines {
            guard !isCancelled() else { return }
            let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
            for run in runs {
                guard let color = (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key.backgroundColor]
                    as? UIColor else { continue }
                let runRange = CTRunGetStringRange(run)
                let x = line.coreTextOrigin.x
                    + CGFloat(CTLineGetOffsetForStringIndex(ctLine, runRange.location, nil))
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                let width = CGFloat(CTRunGetTypographicBounds(
                    run,
                    CFRange(location: 0, length: 0),
                    &ascent,
                    &descent,
                    nil
                ))
                context.setFillColor(color.cgColor)
                context.fill(CGRect(
                    x: x,
                    y: line.coreTextOrigin.y - descent,
                    width: width,
                    height: ascent + descent
                ))
            }
        }
    }

}
