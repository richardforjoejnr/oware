/// One of the two players. `south` sits nearest houses 0–5 (notation A1–A6),
/// `north` sits nearest houses 6–11 (notation B1–B6). Sowing runs counter-clockwise,
/// i.e. in increasing house index, wrapping from 11 back to 0.
public enum Player: Int, Sendable, Codable, Hashable, CaseIterable {
    case south = 0
    case north = 1

    public var opponent: Player { self == .south ? .north : .south }

    /// Absolute house indices owned by this player.
    public var houseRange: Range<Int> { self == .south ? 0..<6 : 6..<12 }

    public func owns(_ house: Int) -> Bool { houseRange.contains(house) }

    /// Notation prefix: "A" for south, "B" for north.
    public var label: String { self == .south ? "A" : "B" }

    public init?(label: String) {
        switch label.uppercased() {
        case "A": self = .south
        case "B": self = .north
        default: return nil
        }
    }
}
