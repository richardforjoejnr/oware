import CoreGraphics
import OwareEngine

/// Geometry shared by the SpriteKit scene (which draws) and the SwiftUI overlay (which receives
/// touches and carries accessibility). Coordinates are SwiftUI-style: origin top-left, y down.
///
/// The board fills the whole area it is given, so on a phone the device itself reads as the board.
/// Two arrangements, both counter-clockwise like a real board:
/// - **Horizontal** (landscape / iPad): north's store, six columns of two houses, south's store.
///   A1…A6 run left to right on the bottom row, B1…B6 right to left on the top row.
/// - **Vertical** (portrait phones): two columns — A1…A6 run bottom to top on the right,
///   B1…B6 top to bottom on the left; south's store sits at the top, north's at the bottom.
struct BoardLayout: Equatable {
    enum Orientation { case horizontal, vertical }

    let size: CGSize
    let orientation: Orientation
    /// Base unit: roughly one house's footprint across the short axis.
    let cell: CGFloat
    let boardRect: CGRect
    /// Distance between neighbouring houses along the long axis (stretches to fill).
    let pitch: CGFloat
    /// Depth of each store zone at the ends, including the board's edge.
    let storeZone: CGFloat

    init(size: CGSize) {
        self.size = size
        boardRect = CGRect(origin: .zero, size: size)
        if size.height > size.width * 1.05 {
            orientation = .vertical
            cell = max(24, min(size.width / 3.6, size.height / 9.0))
            storeZone = cell * 1.25
            pitch = min(cell * 1.4, max(cell * 0.95, (size.height - 2 * storeZone) / 6))
        } else {
            orientation = .horizontal
            cell = max(24, min(size.width / 9.0, size.height / 3.2))
            storeZone = cell * 1.25
            pitch = min(cell * 1.4, max(cell * 0.95, (size.width - 2 * storeZone) / 6))
        }
    }

    var houseRadius: CGFloat { min(cell * 0.5, pitch * 0.47) }
    var seedRadius: CGFloat { cell * 0.095 }
    /// Corner radius of the slab.
    var cornerRadius: CGFloat { cell * 0.45 }

    // MARK: Axis helpers

    /// Position along the long axis of house row/column k = 0 … 5, centred in the playing area.
    private func along(_ k: Int) -> CGFloat {
        let mid = orientation == .vertical ? boardRect.midY : boardRect.midX
        return mid + (CGFloat(k) - 2.5) * pitch
    }
    private var firstLane: CGFloat { (orientation == .vertical ? boardRect.midX : boardRect.midY) - cell * 0.86 }
    private var secondLane: CGFloat { (orientation == .vertical ? boardRect.midX : boardRect.midY) + cell * 0.86 }

    // MARK: Positions

    /// Centre of an absolute house index 0–11.
    func houseCenter(_ index: Int) -> CGPoint {
        switch orientation {
        case .horizontal:
            // south along the bottom (second lane) left→right; north along the top right→left
            if Player.south.owns(index) {
                return CGPoint(x: along(index), y: secondLane)
            } else {
                return CGPoint(x: along(11 - index), y: firstLane)
            }
        case .vertical:
            // south up the right (second lane) bottom→top; north down the left top→bottom
            if Player.south.owns(index) {
                return CGPoint(x: secondLane, y: along(5 - index))
            } else {
                return CGPoint(x: firstLane, y: along(index - 6))
            }
        }
    }

    /// The store (score house) at either end.
    func storeRect(_ player: Player) -> CGRect {
        switch orientation {
        case .horizontal:
            let x = player == .south ? boardRect.maxX - storeZone * 0.52 : boardRect.minX + storeZone * 0.52
            let w = cell * 0.8
            let h = cell * 2.3
            return CGRect(x: x - w / 2, y: boardRect.midY - h / 2, width: w, height: h)
        case .vertical:
            let y = player == .south ? boardRect.minY + storeZone * 0.52 : boardRect.maxY - storeZone * 0.52
            let w = cell * 2.5
            let h = cell * 0.8
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
            return CGPoint(x: c.x, y: c.y + (Player.south.owns(house) ? houseRadius * 1.16 : -houseRadius * 1.16))
        case .vertical:
            return CGPoint(x: c.x + (Player.south.owns(house) ? houseRadius * 1.24 : -houseRadius * 1.24), y: c.y)
        }
    }

    /// Where the sowing hand hovers over a house: toward the board centre, clear of the seeds.
    func handPoint(for house: Int) -> CGPoint {
        let c = houseCenter(house)
        switch orientation {
        case .horizontal:
            return CGPoint(x: c.x, y: c.y + (Player.south.owns(house) ? -cell * 0.5 : cell * 0.5))
        case .vertical:
            return CGPoint(x: c.x + (Player.south.owns(house) ? -cell * 0.5 : cell * 0.5), y: c.y)
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
