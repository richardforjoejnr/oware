import CoreGraphics
import OwareEngine

/// Geometry shared by the SpriteKit scene (which draws) and the SwiftUI overlay (which receives
/// touches and carries accessibility). Coordinates are SwiftUI-style: origin top-left, y down.
///
/// Eight columns: north's store, six houses, south's store. South's houses A1…A6 run left to
/// right on the bottom row; north's B1…B6 run right to left on the top row, so sowing is
/// counter-clockwise on screen exactly as on a real board.
struct BoardLayout: Equatable {
    let size: CGSize
    let cell: CGFloat
    let boardRect: CGRect

    init(size: CGSize) {
        self.size = size
        let horizontal = size.width / 8.6
        let vertical = size.height / 3.4
        cell = max(24, min(horizontal, vertical))
        let width = cell * 8.2
        let height = cell * 2.9
        boardRect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    var houseRadius: CGFloat { cell * 0.42 }
    var seedRadius: CGFloat { cell * 0.075 }

    private func columnX(_ column: Int) -> CGFloat {
        boardRect.minX + cell * 0.1 + cell * (CGFloat(column) + 0.5)
    }

    private var northRowY: CGFloat { boardRect.midY - cell * 0.62 }
    private var southRowY: CGFloat { boardRect.midY + cell * 0.62 }

    /// Centre of an absolute house index 0–11.
    func houseCenter(_ index: Int) -> CGPoint {
        if Player.south.owns(index) {
            return CGPoint(x: columnX(1 + index), y: southRowY)
        } else {
            return CGPoint(x: columnX(12 - index), y: northRowY)
        }
    }

    /// The store (score house) at either end.
    func storeRect(_ player: Player) -> CGRect {
        let x = player == .south ? columnX(7) : columnX(0)
        let w = cell * 0.78
        let h = cell * 2.25
        return CGRect(x: x - w / 2, y: boardRect.midY - h / 2, width: w, height: h)
    }

    /// Where lifted seeds hover while being sown: just above (toward the board centre from) the origin.
    func handPoint(for house: Int) -> CGPoint {
        let c = houseCenter(house)
        let dy: CGFloat = Player.south.owns(house) ? -cell * 0.55 : cell * 0.55
        return CGPoint(x: c.x, y: c.y + dy)
    }

    /// Convert to SpriteKit coordinates (origin bottom-left).
    func sk(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: size.height - p.y) }
    func sk(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height) }

    /// Deterministic resting spot for the k-th seed in a house (sunflower packing).
    func seedSlot(in house: Int, index k: Int) -> CGPoint {
        let c = houseCenter(house)
        let golden = 2.399963
        let angle = Double(k) * golden + Double(house) * 0.7
        let spread = min(houseRadius * 0.62, seedRadius * 1.15 * CGFloat(Double(k).squareRoot()))
        return CGPoint(x: c.x + spread * CGFloat(cos(angle)), y: c.y + spread * CGFloat(sin(angle)))
    }

    /// Resting spot for the k-th seed in a store: fills upward in a loose grid.
    func storeSlot(_ player: Player, index k: Int) -> CGPoint {
        let r = storeRect(player)
        let perRow = 3
        let row = k / perRow
        let col = k % perRow
        let pitch = seedRadius * 2.1
        let x = r.midX + (CGFloat(col) - 1) * pitch + (row % 2 == 0 ? 0 : pitch * 0.35)
        let y = r.maxY - seedRadius * 1.6 - CGFloat(row) * pitch * 0.9
        return CGPoint(x: x, y: max(r.minY + seedRadius * 1.6, y))
    }
}
