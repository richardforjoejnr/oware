import OwareEngine

/// A hand-checkable training position with a single correct answer.
public struct Puzzle: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// Capture at least `target` seeds with one move.
        case captureInOne
        /// Guarantee at least `target` captured seeds within two of your moves, whatever the reply.
        case captureInTwo
        /// Exactly one move avoids losing seeds to the opponent's best reply.
        case escapeTheTrap
        /// The opponent is empty: only one move both feeds them and keeps you safe.
        case feedOrLose
        /// Win the game with one move (reach 25).
        case winInOne

        public var title: String {
            switch self {
            case .captureInOne: "Capture in one"
            case .captureInTwo: "Capture in two"
            case .escapeTheTrap: "Escape the trap"
            case .feedOrLose: "Feed or lose"
            case .winInOne: "Win in one"
            }
        }

        public var instruction: String {
            switch self {
            case .captureInOne: "Find the move that captures the most seeds."
            case .captureInTwo: "Set up a capture the opponent cannot stop."
            case .escapeTheTrap: "Only one move keeps your seeds safe. Find it."
            case .feedOrLose: "The other side is empty. Give them seeds — the right way."
            case .winInOne: "One move wins the game."
            }
        }
    }

    public let id: String
    public let kind: Kind
    /// Houses A1…A6 then B1…B6.
    public let houses: [Int]
    public let stores: [Int]
    public let toMove: Player
    /// The only correct first move.
    public let solution: Move
    /// Seeds gained (or, for traps, seeds saved) by the solution — shown as the goal.
    public let target: Int
    /// Difficulty 1 (easy) … 5 (hard); used for ordering.
    public let difficulty: Int

    public init(id: String, kind: Kind, houses: [Int], stores: [Int], toMove: Player, solution: Move, target: Int, difficulty: Int) {
        self.id = id
        self.kind = kind
        self.houses = houses
        self.stores = stores
        self.toMove = toMove
        self.solution = solution
        self.target = target
        self.difficulty = difficulty
    }

    public var state: GameState {
        GameState(houses: houses, stores: stores, sideToMove: toMove)
    }

    /// Whether `move` solves the puzzle.
    public func isSolved(by move: Move) -> Bool { move == solution }
}

/// A collection loaded from JSON.
public struct PuzzleSet: Sendable, Codable, Hashable {
    public var puzzles: [Puzzle]
    public init(puzzles: [Puzzle]) { self.puzzles = puzzles }

    public func puzzles(of kind: Puzzle.Kind) -> [Puzzle] { puzzles.filter { $0.kind == kind } }

    /// Deterministic daily pick: same puzzle for everyone on the same calendar day.
    public func daily(dayNumber: Int) -> Puzzle? {
        guard !puzzles.isEmpty else { return nil }
        var rng = SeededGenerator(seed: UInt64(dayNumber) &* 0x9E37_79B9_7F4A_7C15)
        return puzzles[Int(rng.next() % UInt64(puzzles.count))]
    }
}
