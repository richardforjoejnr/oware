import CoreGraphics
import LudoEngine

/// Where things sit on screen, from the engine's 15×15 grid: one cell is a fifteenth of the board.
struct BoardLayout {
    let size: CGFloat
    var cell: CGFloat { size / 15 }

    func center(_ c: Board.Cell) -> CGPoint {
        CGPoint(x: (CGFloat(c.column) + 0.5) * cell, y: (CGFloat(c.row) + 0.5) * cell)
    }

    /// The corner a colour's yard fills (6×6 cells), clockwise from top left.
    func yardOrigin(_ color: PlayerColor) -> CGPoint {
        let o: (CGFloat, CGFloat) = [(0, 0), (9, 0), (9, 9), (0, 9)][color.rawValue]
        return CGPoint(x: o.0 * cell, y: o.1 * cell)
    }

    /// Where a token stands: its yard spot, its square, or its colour's corner of the centre.
    func position(_ color: PlayerColor, token: Int, progress: Int) -> CGPoint {
        if progress == Board.yard {
            let spots: [(CGFloat, CGFloat)] = [(2, 2), (4, 2), (2, 4), (4, 4)]
            let o = yardOrigin(color)
            return CGPoint(x: o.x + spots[token].0 * cell, y: o.y + spots[token].1 * cell)
        }
        if progress == Board.home {
            // In the colour's triangle of the centre, side by side across it.
            let c = center(Board.centre)
            let directions: [CGVector] = [CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)]
            let towards = directions[color.rawValue]
            let along: CGFloat = cell * 0.9
            let across: CGFloat = (CGFloat(token) - 1.5) * cell * 0.35
            let x: CGFloat = c.x + towards.dx * along + towards.dy * across
            let y: CGFloat = c.y + towards.dy * along + towards.dx * across
            return CGPoint(x: x, y: y)
        }
        return center(Board.cell(color, progress: progress)!)
    }
}
