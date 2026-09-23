import CoreGraphics
import OwareEngine

/// Geometry shared by the SpriteKit scene (which draws) and the SwiftUI overlay (which receives
/// touches and carries accessibility). Coordinates are SwiftUI-style: origin top-left, y down.
///
/// Two arrangements, both counter-clockwise like a real board:
/// - **Horizontal** (landscape / iPad): eight columns — north's store, six houses, south's store.
///   A1…A6 run left to right on the bottom row, B1…B6 right to left on the top row.
/// - **Vertical** (portrait phones): two columns — A1…A6 run bottom to top on the right,
///   B1…B6 top to bottom on the left; south's store sits at the top, north's at the bottom.
struct BoardLayout: Equatable {
    enum Orientation { case horizontal, vertical }

    let size: CGSize
    let orientation: Orientation
    let cell: CGFloat
    let boardRect: CGRect

    init(size: CGSize) {
        self.size = size
        if size.height > size.width * 1.05 {
            orientation = .vertical
            let horizontal = size.width / 3.6
            let vertical = size.height / 9.2
            cell = max(24, min(horizontal, vertical))
            let width = cell * 3.2
            let height = cell * 8.9
            boardRect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        } else {
            orientation = .horizontal
            let horizontal = size.width / 8.6
            let vertical = size.height / 3.4
            cell = max(24, min(horizontal, vertical))
            let width = cell * 8.2
            let height = cell * 2.9
            boardRect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        }
    }

    var houseRadius: CGFloat { cell * 0.42 }
    var seedRadius: CGFloat { cell * 0.075 }

    // MARK: Horizontal helpers

    private func columnX(_ column: Int) -> CGFloat {
        boardRect.minX + cell * 0.1 + cell * (CGFloat(column) + 0.5)
    }
    private var northRowY: CGFloat { boardRect.midY - cell * 0.62 }
    private var southRowY: CGFloat { boardRect.midY + cell * 0.62 }

    // MARK: Vertical helpers

    /// Row k = 0 (top) … 5 (bottom) of the vertical arrangement.
    private func rowY(_ k: Int) -> CGFloat {
        boardRect.midY + (CGFloat(k) - 2.5) * cell * 1.12
    }
    private var westColumnX: CGFloat { boardRect.midX - cell * 0.62 }
    private var eastColumnX: CGFloat { boardRect.midX + cell * 0.62 }

    // MARK: Positions

    /// Centre of an absolute house index 0–11.
    func houseCenter(_ index: Int) -> CGPoint {
        switch orientation {
        case .horizontal:
            if Player.south.owns(index) {
                return CGPoint(x: columnX(1 + index), y: southRowY)
            } else {
                return CGPoint(x: columnX(12 - index), y: northRowY)
            }
        case .vertical:
            if Player.south.owns(index) {
                return CGPoint(x: eastColumnX, y: rowY(5 - index))
            } else {
                return CGPoint(x: westColumnX, y: rowY(index - 6))
            }
        }
    }

    /// The store (score house) at either end.
    func storeRect(_ player: Player) -> CGRect {
        switch orientation {
        case .horizontal:
            let x = player == .south ? columnX(7) : columnX(0)
            let w = cell * 0.78
            let h = cell * 2.25
            return CGRect(x: x - w / 2, y: boardRect.midY - h / 2, width: w, height: h)
        case .vertical:
            let y = player == .south ? rowY(0) - cell * 1.12 : rowY(5) + cell * 1.12
            let w = cell * 2.25
            let h = cell * 0.78
            return CGRect(x: boardRect.midX - w / 2, y: y - h / 2, width: w, height: h)
        }
    }

    /// Where the store's count is drawn: centred in the store, behind the seeds.
    func storeLabelPoint(_ player: Player) -> CGPoint {
        let r = storeRect(player)
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// Where a house's seed count is drawn (outside the house, away from the board centre).
    func countLabelPoint(_ house: Int) -> CGPoint {
        let c = houseCenter(house)
        switch orientation {
        case .horizontal:
            return CGPoint(x: c.x, y: c.y + (Player.south.owns(house) ? houseRadius * 1.12 : -houseRadius * 1.12))
        case .vertical:
            return CGPoint(x: c.x + (Player.south.owns(house) ? houseRadius * 1.22 : -houseRadius * 1.22), y: c.y)
        }
    }

    /// Where lifted seeds hover while being sown: toward the board centre from the origin.
    func handPoint(for house: Int) -> CGPoint {
        let c = houseCenter(house)
        switch orientation {
        case .horizontal:
            return CGPoint(x: c.x, y: c.y + (Player.south.owns(house) ? -cell * 0.55 : cell * 0.55))
        case .vertical:
            return CGPoint(x: c.x + (Player.south.owns(house) ? -cell * 0.55 : cell * 0.55), y: c.y)
        }
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

    /// Resting spot for the k-th seed in a store: fills from the bottom up in a loose grid.
    func storeSlot(_ player: Player, index k: Int) -> CGPoint {
        let r = storeRect(player)
        let pitch = seedRadius * 2.1
        let columns = max(1, Int((r.width - seedRadius * 1.2) / pitch))
        let row = k / columns
        let col = k % columns
        let x = r.minX + seedRadius * 1.5 + CGFloat(col) * pitch + (row % 2 == 0 ? 0 : pitch * 0.3)
        let y = r.maxY - seedRadius * 1.6 - CGFloat(row) * pitch * 0.9
        return CGPoint(x: min(x, r.maxX - seedRadius * 1.2), y: max(r.minY + seedRadius * 1.6, y))
    }
}
