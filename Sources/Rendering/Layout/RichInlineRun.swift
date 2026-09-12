@preconcurrency import CoreText
import UIKit

final class RichInlineImageAttachment: Sendable {
    let identifier: String
    let image: UIImage?
    let size: CGSize
    let contentInsets: UIEdgeInsets
    let contentMode: UIView.ContentMode
    let tintColor: UIColor?
    let ascent: CGFloat
    let descent: CGFloat

    init(
        identifier: String,
        image: UIImage?,
        size: CGSize,
        contentInsets: UIEdgeInsets,
        font: UIFont,
        contentMode: UIView.ContentMode,
        tintColor: UIColor?
    ) {
        self.identifier = identifier
        self.image = image
        self.size = size
        self.contentInsets = contentInsets
        self.contentMode = contentMode
        self.tintColor = tintColor
        let baselineOffset = (font.ascender + font.descender - size.height) / 2
        ascent = max(0, size.height + baselineOffset)
        descent = max(0, -baselineOffset)
    }
}

final class RichInlineTextBadge: Sendable {
    let line: CTLine
    let backgroundColor: UIColor
    let contentInsets: UIEdgeInsets
    let outerInsets: UIEdgeInsets
    let cornerRadius: CGFloat
    let size: CGSize
    let textDescent: CGFloat
    let ascent: CGFloat
    let descent: CGFloat

    init(
        attributedText: NSAttributedString,
        contentInsets: UIEdgeInsets,
        outerInsets: UIEdgeInsets,
        cornerRadius: CGFloat,
        baselineOffset: CGFloat
    ) {
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let attributes = attributedText.length > 0
            ? attributedText.attributes(at: 0, effectiveRange: nil)
            : [:]
        backgroundColor = attributes[.backgroundColor] as? UIColor ?? .clear
        mutableText.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: mutableText.length))
        self.contentInsets = contentInsets
        self.outerInsets = outerInsets
        self.cornerRadius = max(0, cornerRadius)
        line = CTLineCreateWithAttributedString(mutableText)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        textDescent = descent
        let naturalAscent = ascent + leading + contentInsets.top + outerInsets.top
        let naturalDescent = descent + contentInsets.bottom + outerInsets.bottom
        self.ascent = max(0, naturalAscent + baselineOffset)
        self.descent = max(0, naturalDescent - baselineOffset)
        size = CGSize(
            width: ceil(width) + contentInsets.left + contentInsets.right + outerInsets.left + outerInsets.right,
            height: self.ascent + self.descent
        )
    }
}

final class RichInlineViewAttachment: Sendable {
    let size: CGSize
    let ascent: CGFloat
    let descent: CGFloat

    init(metrics: RichAttachmentMetrics, font: UIFont) {
        size = metrics.occupiedSize
        switch metrics.verticalAlignment {
        case .center:
            let baselineOffset = (
                font.ascender + font.descender - size.height
            ) / 2
            ascent = max(0, size.height + baselineOffset)
            descent = max(0, -baselineOffset)
        case .top:
            ascent = max(0, font.ascender)
            descent = max(0, size.height - ascent)
        case .bottom:
            descent = max(0, -font.descender)
            ascent = max(0, size.height - descent)
        case .baseline:
            ascent = max(0, size.height)
            descent = 0
        }
    }
}

enum RichCoreTextAttribute {
    static let inlineImage = NSAttributedString.Key("io.github.felikslv01.rich-text-view.inline-image")
    static let inlineTextBadge = NSAttributedString.Key("io.github.felikslv01.rich-text-view.inline-text-badge")
    static let inlineViewAttachment = NSAttributedString.Key(
        "io.github.felikslv01.rich-text-view.inline-view-attachment"
    )
    static let truncationToken = NSAttributedString.Key("io.github.felikslv01.rich-text-view.truncation-token")
}

enum RichInlineRunFactory {
    static func viewAttachment(
        metrics: RichAttachmentMetrics,
        font: UIFont
    ) -> NSAttributedString {
        let attachment = RichInlineViewAttachment(
            metrics: metrics,
            font: font
        )
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { reference in
                Unmanaged<RichInlineViewAttachment>
                    .fromOpaque(reference).release()
            },
            getAscent: { reference in
                Unmanaged<RichInlineViewAttachment>
                    .fromOpaque(reference).takeUnretainedValue().ascent
            },
            getDescent: { reference in
                Unmanaged<RichInlineViewAttachment>
                    .fromOpaque(reference).takeUnretainedValue().descent
            },
            getWidth: { reference in
                Unmanaged<RichInlineViewAttachment>
                    .fromOpaque(reference).takeUnretainedValue().size.width
            }
        )
        guard let delegate = CTRunDelegateCreate(
            &callbacks,
            Unmanaged.passRetained(attachment).toOpaque()
        ) else {
            return NSAttributedString(string: "\u{FFFC}")
        }
        return NSAttributedString(
            string: "\u{FFFC}",
            attributes: [
                kCTRunDelegateAttributeName as NSAttributedString.Key: delegate,
                RichCoreTextAttribute.inlineViewAttachment: attachment,
                .foregroundColor: UIColor.clear
            ]
        )
    }

    static func image(
        identifier: String,
        image: UIImage?,
        size: CGSize,
        contentInsets: UIEdgeInsets,
        font: UIFont,
        contentMode: UIView.ContentMode,
        tintColor: UIColor?
    ) -> NSAttributedString {
        let attachment = RichInlineImageAttachment(
            identifier: identifier,
            image: image,
            size: size,
            contentInsets: contentInsets,
            font: font,
            contentMode: contentMode,
            tintColor: tintColor
        )
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { reference in
                Unmanaged<RichInlineImageAttachment>.fromOpaque(reference).release()
            },
            getAscent: { reference in
                Unmanaged<RichInlineImageAttachment>.fromOpaque(reference).takeUnretainedValue().ascent
            },
            getDescent: { reference in
                Unmanaged<RichInlineImageAttachment>.fromOpaque(reference).takeUnretainedValue().descent
            },
            getWidth: { reference in
                Unmanaged<RichInlineImageAttachment>.fromOpaque(reference).takeUnretainedValue().size.width
            }
        )
        guard let delegate = CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(attachment).toOpaque()) else {
            return NSAttributedString(string: "\u{FFFC}")
        }
        return NSAttributedString(
            string: "\u{FFFC}",
            attributes: [
                kCTRunDelegateAttributeName as NSAttributedString.Key: delegate,
                RichCoreTextAttribute.inlineImage: attachment,
                .foregroundColor: UIColor.clear
            ]
        )
    }

    static func textBadge(
        attributedText: NSAttributedString,
        contentInsets: UIEdgeInsets,
        outerInsets: UIEdgeInsets,
        cornerRadius: CGFloat,
        baselineOffset: CGFloat
    ) -> NSAttributedString {
        let badge = RichInlineTextBadge(
            attributedText: attributedText,
            contentInsets: contentInsets,
            outerInsets: outerInsets,
            cornerRadius: cornerRadius,
            baselineOffset: baselineOffset
        )
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { reference in
                Unmanaged<RichInlineTextBadge>.fromOpaque(reference).release()
            },
            getAscent: { reference in
                Unmanaged<RichInlineTextBadge>.fromOpaque(reference).takeUnretainedValue().ascent
            },
            getDescent: { reference in
                Unmanaged<RichInlineTextBadge>.fromOpaque(reference).takeUnretainedValue().descent
            },
            getWidth: { reference in
                Unmanaged<RichInlineTextBadge>.fromOpaque(reference).takeUnretainedValue().size.width
            }
        )
        guard let delegate = CTRunDelegateCreate(&callbacks, Unmanaged.passRetained(badge).toOpaque()) else {
            return attributedText
        }
        return NSAttributedString(
            string: "\u{FFFC}",
            attributes: [
                kCTRunDelegateAttributeName as NSAttributedString.Key: delegate,
                RichCoreTextAttribute.inlineTextBadge: badge,
                .foregroundColor: UIColor.clear
            ]
        )
    }
}

enum RichImageDrawing {
    static func draw(
        _ image: CGImage,
        in rect: CGRect,
        tintColor: UIColor?,
        context: CGContext
    ) {
        guard let tintColor else {
            context.draw(image, in: rect)
            return
        }
        context.saveGState()
        context.clip(to: rect, mask: image)
        context.setFillColor(tintColor.cgColor)
        context.fill(rect)
        context.restoreGState()
    }
}
