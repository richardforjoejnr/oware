import LudoEngine
import SwiftUI

/// The board itself, drawn from the grid in the style of the owner's art: maple squares with dark
/// lines, colours painted on so the grain shows through, yards with an inset maple court, and the
/// centre in the four colours with the black star. Drawn rather than an image so every square sits
/// exactly where `BoardLayout` puts the tokens.
struct BoardCanvas: View {
    let rules: RuleSet

    var body: some View {
        Canvas { ctx, size in
            let layout = BoardLayout(size: size.width)
            let cell = layout.cell
            let wood = GraphicsContext.Shading.tiledImage(Image(Art.maple), scale: max(0.5, size.width / 1024))
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: wood)
            /// Paint over the maple: multiplied, so the grain stays visible under the colour.
            func paint(_ path: Path, _ color: Color) {
                ctx.drawLayer { layer in
                    layer.blendMode = .multiply
                    layer.fill(path, with: .color(color))
                }
            }
            // Yards.
            for color in PlayerColor.allCases {
                let o = layout.yardOrigin(color)
                let yard = CGRect(x: o.x, y: o.y, width: 6 * cell, height: 6 * cell)
                paint(Path(yard), Palette.paint(color))
                // A darker bevel round the painted frame, as on the carved board.
                ctx.stroke(Path(yard.insetBy(dx: cell * 0.08, dy: cell * 0.08)), with: .color(.black.opacity(0.25)), lineWidth: cell * 0.12)
                // The inset maple court with its four squares.
                let court = CGRect(x: o.x + cell, y: o.y + cell, width: 4 * cell, height: 4 * cell)
                ctx.fill(Path(court), with: wood)
                ctx.stroke(Path(court), with: .color(Palette.line), lineWidth: 1.5)
                for spot in [(2.0, 2.0), (4.0, 2.0), (2.0, 4.0), (4.0, 4.0)] {
                    let r = CGRect(x: o.x + (spot.0 - 0.75) * cell, y: o.y + (spot.1 - 0.75) * cell, width: 1.5 * cell, height: 1.5 * cell)
                    ctx.stroke(Path(r), with: .color(Palette.line.opacity(0.55)), lineWidth: 0.8)
                }
            }
            // Track and lanes.
            for (i, c) in Board.track.enumerated() {
                let rect = CGRect(x: CGFloat(c.column) * cell, y: CGFloat(c.row) * cell, width: cell, height: cell)
                if let owner = PlayerColor.allCases.first(where: { Board.startIndex($0) == i }) {
                    paint(Path(rect), Palette.paint(owner))
                }
                if rules.starSquaresSafe && Board.starIndices.contains(i) {
                    ctx.fill(star(in: rect.insetBy(dx: cell * 0.18, dy: cell * 0.18)), with: .color(Palette.line.opacity(0.5)))
                }
                ctx.stroke(Path(rect), with: .color(Palette.line), lineWidth: 1)
            }
            for color in PlayerColor.allCases {
                for c in Board.lane(color) {
                    let rect = CGRect(x: CGFloat(c.column) * cell, y: CGFloat(c.row) * cell, width: cell, height: cell)
                    paint(Path(rect), Palette.paint(color))
                    ctx.stroke(Path(rect), with: .color(Palette.line), lineWidth: 1)
                }
            }
            // Arrows, as painted on the owner's board: out of each start square along the way round,
            // and at each lane's mouth, into the lane.
            for color in PlayerColor.allCases {
                let start = Board.track[Board.startIndex(color)], next = Board.track[Board.startIndex(color) + 1]
                arrow(ctx, at: start, towards: next, cell: cell, color: .white.opacity(0.9))
                let mouth = Board.track[Board.entranceIndex(color)], first = Board.lane(color)[0]
                arrow(ctx, at: mouth, towards: first, cell: cell, color: Palette.line.opacity(0.8))
            }
            // Centre: four triangles towards each colour's lane, and the black star.
            let centre = CGRect(x: 6 * cell, y: 6 * cell, width: 3 * cell, height: 3 * cell)
            let mid = CGPoint(x: centre.midX, y: centre.midY)
            let corners = [CGPoint(x: centre.minX, y: centre.minY), CGPoint(x: centre.maxX, y: centre.minY),
                           CGPoint(x: centre.maxX, y: centre.maxY), CGPoint(x: centre.minX, y: centre.maxY)]
            // Left side → red, top → yellow, right → black, bottom → green (each lane's side).
            let sides: [(PlayerColor, CGPoint, CGPoint)] = [(.red, corners[3], corners[0]), (.yellow, corners[0], corners[1]),
                                                            (.black, corners[1], corners[2]), (.green, corners[2], corners[3])]
            for (color, a, b) in sides {
                var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: mid); p.closeSubpath()
                paint(p, Palette.paint(color))
                ctx.stroke(p, with: .color(Palette.line), lineWidth: 1)
            }
            // The black star of the flag, on a gold square as on the owner's board.
            let gold = centre.insetBy(dx: cell * 0.85, dy: cell * 0.85)
            paint(Path(gold), Palette.paint(.yellow))
            ctx.stroke(Path(gold), with: .color(Palette.line), lineWidth: 1)
            ctx.fill(star(in: centre.insetBy(dx: cell * 0.55, dy: cell * 0.55)), with: .color(Color(red: 0.06, green: 0.05, blue: 0.04)))
            ctx.stroke(star(in: centre.insetBy(dx: cell * 0.55, dy: cell * 0.55)), with: .color(Palette.brass), lineWidth: 1)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// A small arrow in a square, pointing at the neighbouring square.
    private func arrow(_ ctx: GraphicsContext, at c: Board.Cell, towards n: Board.Cell, cell: CGFloat, color: Color) {
        let mid = CGPoint(x: (CGFloat(c.column) + 0.5) * cell, y: (CGFloat(c.row) + 0.5) * cell)
        let dx = CGFloat(n.column - c.column), dy = CGFloat(n.row - c.row)
        let len = max(1, hypot(dx, dy)), ux = dx / len, uy = dy / len
        let s = cell * 0.28
        var p = Path()
        p.move(to: CGPoint(x: mid.x - ux * s, y: mid.y - uy * s))
        p.addLine(to: CGPoint(x: mid.x + ux * s, y: mid.y + uy * s))
        p.move(to: CGPoint(x: mid.x + ux * s - (ux + uy) * s * 0.55, y: mid.y + uy * s - (uy - ux) * s * 0.55))
        p.addLine(to: CGPoint(x: mid.x + ux * s, y: mid.y + uy * s))
        p.addLine(to: CGPoint(x: mid.x + ux * s - (ux - uy) * s * 0.55, y: mid.y + uy * s - (uy + ux) * s * 0.55))
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: max(1.5, cell * 0.08), lineCap: .round, lineJoin: .round))
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
