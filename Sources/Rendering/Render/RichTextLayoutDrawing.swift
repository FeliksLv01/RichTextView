import UIKit

extension RichTextLayout {
    func draw(in context: CGContext, size: CGSize, loadedImages: [String: UIImage] = [:], isCancelled: () -> Bool = { false }) {
        let clip = context.boundingBoxOfClipPath
        let visible = CGRect(x: clip.minX, y: size.height - clip.maxY, width: clip.width, height: clip.height)
        let indices = drawingIndices(in: visible)
        for index in indices.reversed() {
            if isCancelled() { return }
            let runBox = runBoxes[index]
            guard runBox.frame.intersects(visible) else { continue }
            guard let decorationRunBox = runBox as? RichDecorationRunBox else { continue }
            let color: UIColor
            let cornerRadius: CGFloat
            let roundsTopCornersOnly: Bool
            switch decorationRunBox.decoration {
            case let .background(backgroundColor, radius),
                 let .borderedBackground(backgroundColor, radius, _, _):
                color = backgroundColor
                cornerRadius = radius
                roundsTopCornersOnly = false
            case let .topRoundedBackground(backgroundColor, radius):
                color = backgroundColor
                cornerRadius = radius
                roundsTopCornersOnly = true
            default:
                continue
            }
            let rect = CGRect(
                x: decorationRunBox.frame.minX,
                y: size.height - decorationRunBox.frame.maxY,
                width: decorationRunBox.frame.width,
                height: decorationRunBox.frame.height
            )
            context.setFillColor(color.cgColor)
            if roundsTopCornersOnly {
                let radius = min(max(0, cornerRadius), min(rect.width, rect.height) / 2)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
                path.addArc(
                    center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                    radius: radius,
                    startAngle: 0,
                    endAngle: .pi / 2,
                    clockwise: false
                )
                path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
                path.addArc(
                    center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                    radius: radius,
                    startAngle: .pi / 2,
                    endAngle: .pi,
                    clockwise: false
                )
                path.closeSubpath()
                context.addPath(path)
            } else {
                context.addPath(CGPath(
                    roundedRect: rect,
                    cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius,
                    transform: nil
                ))
            }
            context.fillPath()
        }
        for index in indices {
            let runBox = runBoxes[index]
            guard runBox.frame.intersects(visible) else { continue }
            if isCancelled() { return }
            if let textRunBox = runBox as? RichTextRunBox {
                textRunBox.layout.draw(
                    in: context,
                    canvasHeight: size.height,
                    origin: textRunBox.frame.origin,
                    imageResolver: { loadedImages[$0] },
                    isCancelled: isCancelled
                )
            } else if let imageRunBox = runBox as? RichImageRunBox,
                      let image = (loadedImages[imageRunBox.element.source.identifier]
                          ?? imageRunBox.element.source.image)?.cgImage {
                let imageFrame = CGRect(
                    x: imageRunBox.frame.minX,
                    y: size.height - imageRunBox.frame.maxY,
                    width: imageRunBox.frame.width,
                    height: imageRunBox.frame.height
                )
                RichImageDrawing.draw(
                    image,
                    in: RichImageDrawing.fittedRect(
                        imageSize: CGSize(width: image.width, height: image.height),
                        in: imageFrame,
                        contentInsets: imageRunBox.element.contentInsets,
                        contentMode: imageRunBox.element.contentMode
                    ),
                    tintColor: imageRunBox.element.tintColor,
                    context: context
                )
            } else if let decorationRunBox = runBox as? RichDecorationRunBox {
                switch decorationRunBox.decoration {
                case .background, .topRoundedBackground:
                    continue
                case let .borderedBackground(_, cornerRadius, borderColor, borderWidth):
                    guard borderWidth > 0 else { continue }
                    let inset = borderWidth / 2
                    let rect = CGRect(
                        x: decorationRunBox.frame.minX,
                        y: size.height - decorationRunBox.frame.maxY,
                        width: decorationRunBox.frame.width,
                        height: decorationRunBox.frame.height
                    ).insetBy(dx: inset, dy: inset)
                    context.setStrokeColor(borderColor.cgColor)
                    context.setLineWidth(borderWidth)
                    context.addPath(CGPath(
                        roundedRect: rect,
                        cornerWidth: max(0, cornerRadius - inset),
                        cornerHeight: max(0, cornerRadius - inset),
                        transform: nil
                    ))
                    context.strokePath()
                case let .verticalGradient(topColor, bottomColor):
                    let rect = CGRect(
                        x: decorationRunBox.frame.minX,
                        y: size.height - decorationRunBox.frame.maxY,
                        width: decorationRunBox.frame.width,
                        height: decorationRunBox.frame.height
                    )
                    guard let gradient = CGGradient(
                        colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [bottomColor.cgColor, topColor.cgColor] as CFArray,
                        locations: [0, 1]
                    ) else { continue }
                    context.saveGState()
                    context.clip(to: rect)
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: rect.midX, y: rect.minY),
                        end: CGPoint(x: rect.midX, y: rect.maxY),
                        options: []
                    )
                    context.restoreGState()
                case let .leadingRule(color, _):
                    context.setFillColor(color.cgColor)
                    context.fill(CGRect(
                        x: decorationRunBox.frame.minX,
                        y: size.height - decorationRunBox.frame.maxY,
                        width: decorationRunBox.frame.width,
                        height: decorationRunBox.frame.height
                    ))
                case .listMarker:
                    decorationRunBox.textLayout?.draw(
                        in: context,
                        canvasHeight: size.height,
                        origin: decorationRunBox.frame.origin,
                        imageResolver: { loadedImages[$0] },
                        isCancelled: isCancelled
                    )
                case let .horizontalRule(color):
                    context.setFillColor(color.cgColor)
                    context.fill(CGRect(
                        x: decorationRunBox.frame.minX,
                        y: size.height - decorationRunBox.frame.maxY,
                        width: decorationRunBox.frame.width,
                        height: decorationRunBox.frame.height
                    ))
                }
            }
        }
    }
}
