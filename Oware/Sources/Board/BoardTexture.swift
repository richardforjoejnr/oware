import SpriteKit
import UIKit

/// Bakes the board slab: tiled osese wood, a rounded silhouette, a warm key light from the
/// upper left, and a dark vignette so the hollows read as depth. Rebuilt only when the size changes.
enum BoardTexture {
    static func make(size: CGSize, cornerRadius: CGFloat) -> SKTexture {
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
                // Tile at a scale that keeps the adze marks readable on any board size.
                let tile = max(size.width, size.height) / 2.2
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

            // Worn, slightly lighter edge where hands rest.
            cg.setStrokeColor(UIColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 0.35).cgColor)
            cg.setLineWidth(2)
            UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: cornerRadius - 1).stroke()
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
