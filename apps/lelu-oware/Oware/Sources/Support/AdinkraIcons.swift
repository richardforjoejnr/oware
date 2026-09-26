import SwiftUI

/// Vector Adinkra glyphs used as UI icons (GAME_PLAN §3.3): Sankofa for Undo, Nyansapo for Hint.
/// Both are drawn in a unit square and stroked, so they read cleanly at button size and scale
/// with Dynamic Type. Meanings and sources are logged in `docs/CULTURE_SOURCES.md`.
enum Adinkra {
    /// Sankofa, the bird that turns its head to fetch the egg from its back:
    /// "go back and take it" — learning from the past. Used for Undo.
    struct Sankofa: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            // Body: a slender lens with the tail lifted, then belly, breast and back.
            p.move(to: pt(0.04, 0.48))
            p.addCurve(to: pt(0.58, 0.84), control1: pt(0.08, 0.80), control2: pt(0.40, 0.90))
            p.addCurve(to: pt(0.78, 0.60), control1: pt(0.74, 0.82), control2: pt(0.82, 0.72))
            p.addCurve(to: pt(0.04, 0.48), control1: pt(0.70, 0.50), control2: pt(0.36, 0.58))
            p.closeSubpath()
            // Neck rising from the breast, head curling back over the body, beak towards the egg.
            p.move(to: pt(0.74, 0.58))
            p.addCurve(to: pt(0.66, 0.16), control1: pt(0.90, 0.46), control2: pt(0.86, 0.16))
            p.addCurve(to: pt(0.50, 0.31), control1: pt(0.54, 0.16), control2: pt(0.46, 0.22))
            // The egg on its back.
            let egg = pt(0.47, 0.42)
            p.addEllipse(in: CGRect(x: egg.x - 0.045 * rect.width, y: egg.y - 0.045 * rect.height,
                                    width: 0.09 * rect.width, height: 0.09 * rect.height))
            // Legs.
            p.move(to: pt(0.38, 0.86)); p.addLine(to: pt(0.35, 0.97))
            p.move(to: pt(0.52, 0.87)); p.addLine(to: pt(0.55, 0.97))
            return p
        }
    }

    /// Nyansapo, the wisdom knot: a strand looping out at each corner of a small square.
    /// Wisdom, ingenuity, patience. Used for Hint.
    struct Nyansapo: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            func unit(_ v: CGVector) -> CGVector {
                let len = max(hypot(v.dx, v.dy), 0.0001)
                return CGVector(dx: v.dx / len, dy: v.dy / len)
            }
            func add(_ a: CGPoint, _ v: CGVector, _ k: CGFloat) -> CGPoint {
                CGPoint(x: a.x + v.dx * k * rect.width, y: a.y + v.dy * k * rect.height)
            }
            let s: CGFloat = 0.11            // half side of the inner square
            let reach: CGFloat = 0.36        // how far each loop reaches past its corner
            let pull: CGFloat = 0.24         // control-point distance
            let corners = [pt(0.5 - s, 0.5 + s), pt(0.5 - s, 0.5 - s), pt(0.5 + s, 0.5 - s), pt(0.5 + s, 0.5 + s)]
            p.move(to: corners[0])
            for i in 0..<4 {
                let a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4]
                let d1 = unit(CGVector(dx: b.x - a.x, dy: b.y - a.y))   // arriving direction
                let d2 = unit(CGVector(dx: c.x - b.x, dy: c.y - b.y))   // leaving direction
                let diag = unit(CGVector(dx: d1.dx - d2.dx, dy: d1.dy - d2.dy))
                let apexTangent = unit(CGVector(dx: -(d1.dx + d2.dx), dy: -(d1.dy + d2.dy)))
                let apex = add(b, diag, reach)
                p.addLine(to: b)
                p.addCurve(to: apex, control1: add(b, d1, pull), control2: add(apex, apexTangent, -pull))
                p.addCurve(to: b, control1: add(apex, apexTangent, pull), control2: add(b, d2, -pull))
            }
            p.closeSubpath()
            return p
        }
    }
}

/// A stroked Adinkra glyph sized like an SF Symbol icon.
struct AdinkraGlyph<S: Shape>: View {
    let shape: S
    var size: CGFloat = 20
    var lineWidth: CGFloat = 1.6
    var color: Color = Theme.ivoryDim

    var body: some View {
        shape
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
