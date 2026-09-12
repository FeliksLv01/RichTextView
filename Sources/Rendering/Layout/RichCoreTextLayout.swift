@preconcurrency import CoreText
import UIKit

final class RichCoreTextLayout: @unchecked Sendable {
    struct LineFragment: Sendable {
        let line: CTLine
        let range: NSRange
        let frame: CGRect
        let coreTextOrigin: CGPoint
        let stringIndexOffset: Int
    }

    let attributedText: NSAttributedString
    let framesetter: CTFramesetter
    let frame: CTFrame
    let size: CGSize
    let lines: [LineFragment]

    init?(
        attributedText: NSAttributedString,
        constrainedWidth: CGFloat,
        maximumNumberOfLines: Int = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) {
        guard attributedText.length > 0, constrainedWidth > 0 else { return nil }
        self.attributedText = NSAttributedString(attributedString: attributedText)
        framesetter = CTFramesetterCreateWithAttributedString(self.attributedText)
        // 不折行模式（.byClipping）：用超大宽度排版让长行不换行，输出真实内容宽度（可超出约束宽度），
        // 供外层横向滚动承载。其余模式沿用约束宽度排版与 clamp。
        let isNonWrapping = lineBreakMode == .byClipping
        let layoutWidth = isNonWrapping ? 100_000 : min(100_000, constrainedWidth)
        let safeWidth = layoutWidth
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            nil,
            CGSize(width: safeWidth, height: 100_000),
            nil
        )
        let fullHeight = max(1, ceil(suggested.height))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: safeWidth, height: fullHeight), transform: nil)
        frame = CTFramesetterCreateFrame(
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
        let rawFragments = orderedLines.prefix(lineLimit).map { line, origin in
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let range = CTLineGetStringRange(line)
            return (
                line: line,
                range: NSRange(location: range.location, length: range.length),
                origin: origin,
                ascent: ascent,
                descent: descent,
                leading: leading,
                width: width
            )
        }
        let visibleHeight = ceil(rawFragments.map {
            fullHeight - $0.origin.y + $0.descent + $0.leading
        }.max() ?? 0)
        let shouldTruncate = maximumNumberOfLines > 0
            && lineLimit > 0
            && allLines.count > lineLimit
            && Self.truncationType(for: lineBreakMode) != nil
        var fragments: [LineFragment] = []
        for (index, raw) in rawFragments.enumerated() {
            var line = raw.line
            var range = raw.range
            var stringIndexOffset = 0
            if shouldTruncate,
               index == rawFragments.count - 1,
               let truncationType = Self.truncationType(for: lineBreakMode) {
                let remainingRange = NSRange(
                    location: raw.range.location,
                    length: self.attributedText.length - raw.range.location
                )
                let remainingText = self.attributedText.attributedSubstring(from: remainingRange)
                let candidate = CTLineCreateWithAttributedString(remainingText)
                let token = Self.truncationToken(
                    for: self.attributedText,
                    location: raw.range.location
                )
                if let truncated = CTLineCreateTruncatedLine(candidate, Double(safeWidth), truncationType, token) {
                    line = truncated
                    range = Self.visibleSourceRange(
                        in: truncated,
                        sourceOffset: raw.range.location,
                        fallback: raw.range
                    )
                    stringIndexOffset = raw.range.location
                }
            }
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let y = max(0, fullHeight - raw.origin.y - ascent)
            fragments.append(LineFragment(
                line: line,
                range: range,
                frame: CGRect(
                    x: raw.origin.x,
                    y: y,
                    width: ceil(min(safeWidth, width)),
                    height: ceil(ascent + descent + leading)
                ),
                coreTextOrigin: CGPoint(
                    x: raw.origin.x,
                    y: visibleHeight - y - ascent
                ),
                stringIndexOffset: stringIndexOffset
            ))
        }
        lines = fragments
        let measuredWidth = fragments.map(\.frame.maxX).max() ?? min(safeWidth, ceil(suggested.width))
        size = CGSize(width: min(safeWidth, ceil(measuredWidth)), height: visibleHeight)
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
        drawRunBackgrounds(in: context, isCancelled: isCancelled)
        for line in lines {
            guard !isCancelled() else { break }
            context.textPosition = line.coreTextOrigin
            CTLineDraw(line.line, context)
        }
        drawInlineTextBadges(in: context, isCancelled: isCancelled)
        drawInlineImages(in: context, imageResolver: imageResolver, isCancelled: isCancelled)
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
        guard let line = closestLine(to: point) else { return nil }
        let relative = CGPoint(x: max(0, point.x - line.frame.minX), y: 0)
        let index = CTLineGetStringIndexForPosition(line.line, relative)
        guard index != kCFNotFound else { return NSMaxRange(line.range) }
        let sourceIndex = line.stringIndexOffset + index
        return min(NSMaxRange(line.range), max(line.range.location, sourceIndex))
    }

    func lineRange(at point: CGPoint) -> NSRange? {
        closestLine(to: point)?.range
    }

    /// ICU 按词切分（与系统文本选择一致，中文为词粒度而非标点间整句）；
    /// 点位不在任何词上时回落到该处的 composed character。
    func wordRange(at point: CGPoint) -> NSRange? {
        guard let line = closestLine(to: point),
              let position = closestPosition(to: point) else { return nil }
        let string = attributedText.string as NSString
        guard string.length > 0 else { return nil }
        let index = min(max(line.range.location, position), NSMaxRange(line.range) - 1)
        guard index >= 0, index < string.length else { return nil }
        var match: NSRange?
        string.enumerateSubstrings(
            in: line.range,
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
        lines.compactMap { line in
            let intersection = NSIntersectionRange(range, line.range)
            guard intersection.length > 0 else { return nil }
            let start = CGFloat(CTLineGetOffsetForStringIndex(
                line.line,
                intersection.location - line.stringIndexOffset,
                nil
            ))
            let end = CGFloat(CTLineGetOffsetForStringIndex(
                line.line,
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

    func inlineRunRect(at location: Int) -> CGRect? {
        for line in lines where NSLocationInRange(location, line.range) {
            let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []
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
                    line.line,
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
                        line.line,
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

    private func closestLine(to point: CGPoint) -> LineFragment? {
        if let contained = lines.first(where: { $0.frame.insetBy(dx: 0, dy: -4).contains(point) }) {
            return contained
        }
        return lines.min { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) }
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
        imageResolver: ((String) -> UIImage?)?,
        isCancelled: () -> Bool
    ) {
        for line in lines {
            guard !isCancelled() else { return }
            let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []
            for run in runs {
                guard let attachment = (CTRunGetAttributes(run) as NSDictionary)[RichCoreTextAttribute.inlineImage]
                    as? RichInlineImageAttachment,
                    let image = (imageResolver?(attachment.identifier) ?? attachment.image)?.cgImage else { continue }
                let runRange = CTRunGetStringRange(run)
                let x = line.coreTextOrigin.x
                    + CGFloat(CTLineGetOffsetForStringIndex(line.line, runRange.location, nil))
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

    private func drawInlineTextBadges(in context: CGContext, isCancelled: () -> Bool) {
        for line in lines {
            guard !isCancelled() else { return }
            let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []
            for run in runs {
                guard let badge = (CTRunGetAttributes(run) as NSDictionary)[RichCoreTextAttribute.inlineTextBadge]
                    as? RichInlineTextBadge else { continue }
                let runRange = CTRunGetStringRange(run)
                let x = line.coreTextOrigin.x
                    + CGFloat(CTLineGetOffsetForStringIndex(line.line, runRange.location, nil))
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
                CTLineDraw(badge.line, context)
            }
        }
    }

    private func drawRunBackgrounds(in context: CGContext, isCancelled: () -> Bool) {
        for line in lines {
            guard !isCancelled() else { return }
            let runs = CTLineGetGlyphRuns(line.line) as? [CTRun] ?? []
            for run in runs {
                guard let color = (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key.backgroundColor]
                    as? UIColor else { continue }
                let runRange = CTRunGetStringRange(run)
                let x = line.coreTextOrigin.x
                    + CGFloat(CTLineGetOffsetForStringIndex(line.line, runRange.location, nil))
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
