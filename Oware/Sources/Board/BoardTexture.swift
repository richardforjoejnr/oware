import SpriteKit
import UIKit

/// Bakes the board slab: tiled osese wood, a rounded silhouette, a warm key light from the
/// upper left, and a dark vignette so the hollows read as depth. Rebuilt only when the size changes.
enum BoardTexture {
    static func make(size: CGSize, cornerRadius: CGFloat, scorched: Bool = false) -> SKTexture {
        let scale = min(UIScreen.main.scale, 3)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            path.addClip()

            if let wood = UIImage(named: "wood") {
                // One tile covers the whole slab so no repeat is visible; the grain runs along the board.
                let tile = max(size.width, size.height) * 1.02
                cg.saveGState()
                cg.setFillColor(UIColor(patternImage: scaled(wood, to: tile)).cgColor)
                cg.fill(rect)
                cg.restoreGState()
            } else {
                cg.setFillColor(UIColor(red: 0.24, green: 0.145, blue: 0.09, alpha: 1).cgColor)
                cg.fill(rect)
            }

            // Key light: warm lift from the upper left, gentle fall-off to the lower right.
            let rgb = CGColorSpaceCreateDeviceRGB()
            func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
                CGColor(colorSpace: rgb, components: [r, g, b, a]) ?? UIColor(red: r, green: g, blue: b, alpha: a).cgColor
            }
            if let light = CGGradient(colorsSpace: rgb,
                                      colors: [c(1, 0.85, 0.6, 0.18), c(0, 0, 0, 0), c(0, 0, 0, 0.28)] as CFArray,
                                      locations: [0, 0.45, 1]) {
                cg.drawLinearGradient(light, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])
            }

            // Vignette toward the edges.
            if let vignette = CGGradient(colorsSpace: rgb,
                                         colors: [c(0, 0, 0, 0), c(0, 0, 0, 0.35)] as CFArray,
                                         locations: [0.55, 1]) {
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                cg.drawRadialGradient(vignette, startCenter: centre, startRadius: 0, endCenter: centre,
                                      endRadius: max(size.width, size.height) * 0.62, options: [.drawsAfterEndLocation])
            }

            if scorched {
                // Fire-blackened edges: several soft dark strokes of decreasing width, then a ragged
                // inner line so the burn does not read as a clean vignette.
                let band = min(size.width, size.height) * 0.13
                for (k, alpha) in [0.55, 0.42, 0.32, 0.22, 0.14, 0.08].enumerated() {
                    let width = band * (1.0 - CGFloat(k) * 0.14)
                    cg.setStrokeColor(UIColor(red: 0.07, green: 0.045, blue: 0.03, alpha: CGFloat(alpha)).cgColor)
                    let burn = UIBezierPath(roundedRect: rect.insetBy(dx: width * 0.15, dy: width * 0.15), cornerRadius: cornerRadius)
                    burn.lineWidth = width   // UIBezierPath strokes with its own width, not the context's
                    burn.stroke()
                }
                var generator = SystemRandomNumberGenerator()
                let ragged = UIBezierPath()
                let inset = band * 0.62
                let steps = 140
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let perimeter = UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), cornerRadius: max(2, cornerRadius - inset))
                    let point = perimeter.cgPath.point(atFraction: t)
                    let jitter = CGFloat.random(in: -band * 0.12 ... band * 0.12, using: &generator)
                    let p = CGPoint(x: point.x + jitter, y: point.y + CGFloat.random(in: -band * 0.12 ... band * 0.12, using: &generator))
                    i == 0 ? ragged.move(to: p) : ragged.addLine(to: p)
                }
                ragged.close()
                cg.setStrokeColor(UIColor(red: 0.05, green: 0.03, blue: 0.02, alpha: 0.5).cgColor)
                ragged.lineWidth = max(1.5, band * 0.05)
                ragged.stroke()
            } else {
                // Worn, slightly lighter edge where hands rest.
                cg.setStrokeColor(UIColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 0.35).cgColor)
                let worn = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: cornerRadius - 1)
                worn.lineWidth = 2
                worn.stroke()
            }
        }
        return SKTexture(image: image)
    }

    /// A strip of the carved Kente relief, tiled along its length so the motifs never stretch.
    static func band(length: CGFloat, thickness: CGFloat) -> SKTexture {
        let scale = min(UIScreen.main.scale, 3)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let size = CGSize(width: max(length, 1), height: max(thickness, 1))
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            guard let relief = UIImage(named: "rimCarved") else { return }
            let tileWidth = thickness * relief.size.width / relief.size.height
            var x: CGFloat = -tileWidth * 0.5
            while x < size.width {
                relief.draw(in: CGRect(x: x, y: 0, width: tileWidth, height: thickness))
                x += tileWidth
            }
            // Recess the band a little: dark line above, faint highlight below.
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(white: 0, alpha: 0.45).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size.width, height: max(1, thickness * 0.05)))
            cg.setFillColor(UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.18).cgColor)
            cg.fill(CGRect(x: 0, y: size.height - max(1, thickness * 0.04), width: size.width, height: max(1, thickness * 0.04)))
        }
        return SKTexture(image: image)
    }

    private static func scaled(_ image: UIImage, to side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}

private extension CGPath {
    /// A point a fraction of the way round a flattened path (good enough for a jittered outline).
    func point(atFraction fraction: CGFloat) -> CGPoint {
        var points: [CGPoint] = []
        applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: points.append(element.pointee.points[0])
            case .addQuadCurveToPoint: points.append(element.pointee.points[1])
            case .addCurveToPoint: points.append(element.pointee.points[2])
            default: break
            }
        }
        guard points.count > 1 else { return points.first ?? .zero }
        // Walk the polyline by length.
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count { lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)) }
        let closing = hypot(points[0].x - points[points.count - 1].x, points[0].y - points[points.count - 1].y)
        let total = lengths[lengths.count - 1] + closing
        let target = max(0, min(1, fraction)) * total
        for i in 1..<points.count where lengths[i] >= target {
            let segment = lengths[i] - lengths[i - 1]
            let t = segment > 0 ? (target - lengths[i - 1]) / segment : 0
            return CGPoint(x: points[i - 1].x + (points[i].x - points[i - 1].x) * t, y: points[i - 1].y + (points[i].y - points[i - 1].y) * t)
        }
        let t = closing > 0 ? (target - lengths[lengths.count - 1]) / closing : 0
        let a = points[points.count - 1], b = points[0]
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
