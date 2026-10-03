import LudoEngine
import SwiftUI

/// The board itself, drawn from the grid: yards, the cream track, coloured starts and lanes, the
/// centre in the four colours with the black star. Replaced by the owner's art later; tokens are
/// placed from `BoardLayout`, so the art can change without moving anything.
struct BoardCanvas: View {
    let rules: RuleSet

    var body: some View {
        Canvas { ctx, size in
            let layout = BoardLayout(size: size.width)
            let cell = layout.cell
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.cream))
            // Yards.
            for color in PlayerColor.allCases {
                let o = layout.yardOrigin(color)
                ctx.fill(Path(CGRect(x: o.x, y: o.y, width: 6 * cell, height: 6 * cell)), with: .color(Palette.color(color)))
                ctx.fill(Path(roundedRect: CGRect(x: o.x + cell, y: o.y + cell, width: 4 * cell, height: 4 * cell), cornerRadius: cell * 0.4),
                         with: .color(Palette.cream))
                for spot in [(2.0, 2.0), (4.0, 2.0), (2.0, 4.0), (4.0, 4.0)] {
                    let r = CGRect(x: o.x + (spot.0 - 0.38) * cell, y: o.y + (spot.1 - 0.38) * cell, width: 0.76 * cell, height: 0.76 * cell)
                    ctx.stroke(Path(ellipseIn: r), with: .color(Palette.color(color).opacity(0.6)), lineWidth: 1.5)
                }
            }
            // Track and lanes.
            for (i, c) in Board.track.enumerated() {
                let rect = CGRect(x: CGFloat(c.column) * cell, y: CGFloat(c.row) * cell, width: cell, height: cell)
                if let owner = PlayerColor.allCases.first(where: { Board.startIndex($0) == i }) {
                    ctx.fill(Path(rect), with: .color(Palette.color(owner).opacity(0.85)))
                }
                if rules.starSquaresSafe && Board.starIndices.contains(i) {
                    ctx.fill(star(in: rect.insetBy(dx: cell * 0.18, dy: cell * 0.18)), with: .color(Palette.line.opacity(0.5)))
                }
                ctx.stroke(Path(rect), with: .color(Palette.line.opacity(0.6)), lineWidth: 0.8)
            }
            for color in PlayerColor.allCases {
                for c in Board.lane(color) {
                    let rect = CGRect(x: CGFloat(c.column) * cell, y: CGFloat(c.row) * cell, width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color(Palette.color(color).opacity(0.85)))
                    ctx.stroke(Path(rect), with: .color(Palette.line.opacity(0.6)), lineWidth: 0.8)
                }
            }
            // Centre: four triangles towards each colour's lane, and the black star.
            let centre = CGRect(x: 6 * cell, y: 6 * cell, width: 3 * cell, height: 3 * cell)
            let mid = CGPoint(x: centre.midX, y: centre.midY)
            let corners = [CGPoint(x: centre.minX, y: centre.minY), CGPoint(x: centre.maxX, y: centre.minY),
                           CGPoint(x: centre.maxX, y: centre.maxY), CGPoint(x: centre.minX, y: centre.maxY)]
            // Left side → red, top → gold, right → black, bottom → green (each lane's side).
            let sides: [(PlayerColor, CGPoint, CGPoint)] = [(.red, corners[3], corners[0]), (.gold, corners[0], corners[1]),
                                                            (.black, corners[1], corners[2]), (.green, corners[2], corners[3])]
            for (color, a, b) in sides {
                var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: mid); p.closeSubpath()
                ctx.fill(p, with: .color(Palette.color(color)))
            }
            ctx.fill(star(in: centre.insetBy(dx: cell * 0.75, dy: cell * 0.75)), with: .color(.black))
            ctx.stroke(star(in: centre.insetBy(dx: cell * 0.75, dy: cell * 0.75)), with: .color(Palette.brass), lineWidth: 1)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// A five-pointed star, point up.
    private func star(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), outer = min(rect.width, rect.height) / 2, inner = outer * 0.4
        for i in 0..<10 {
            let r = i % 2 == 0 ? outer : inner
            let a = Double(i) * .pi / 5 - .pi / 2
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
