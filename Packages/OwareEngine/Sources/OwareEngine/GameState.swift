/// Pure, UI-independent Oware (Abapa) rules engine.
///
/// This is a minimal stub so the package builds and CI runs. The full rules
/// (sowing, origin skip, 2/3 captures, grand slam, feeding obligation,
/// endgame and cycle detection) land in Milestone 1 — see docs/GAME_PLAN.md.
public struct GameState: Sendable, Equatable, Codable {
    /// Houses 0–5 belong to player A (south), 6–11 to player B (north),
    /// indexed counter-clockwise.
    public var houses: [Int]
    public var stores: [Int]

    public static let houseCount = 12
    public static let seedsPerHouse = 4

    public init(houses: [Int], stores: [Int]) {
        precondition(houses.count == Self.houseCount, "Oware has 12 houses")
        precondition(stores.count == 2, "Two players, two stores")
        self.houses = houses
        self.stores = stores
    }

    public static let initial = GameState(
        houses: Array(repeating: seedsPerHouse, count: houseCount),
        stores: [0, 0]
    )

    public var seedsOnBoard: Int { houses.reduce(0, +) }
    public var totalSeeds: Int { seedsOnBoard + stores.reduce(0, +) }
}
