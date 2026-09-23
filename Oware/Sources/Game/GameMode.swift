import OwareEngine
import OwareAI

/// Who is playing whom.
enum GameMode: Codable, Hashable, Sendable {
    case versusAI(difficulty: Difficulty, personality: Personality, humanPlays: Player)
    case passAndPlay
    /// A single-move training position; only the puzzle's solution counts.
    case puzzle(Puzzle)
    /// The guided lesson; `step` indexes `Tutorial.steps`.
    case tutorial(step: Int)

    var aiSide: Player? {
        if case let .versusAI(_, _, human) = self { return human.opponent }
        return nil
    }

    var aiPlayer: AIPlayer? {
        if case let .versusAI(difficulty, personality, _) = self {
            return AIPlayer(difficulty: difficulty, personality: personality)
        }
        return nil
    }

    /// Modes that are ordinary games worth saving and resuming.
    var isResumable: Bool {
        switch self {
        case .versusAI, .passAndPlay: true
        case .puzzle, .tutorial: false
        }
    }

    var title: String {
        switch self {
        case let .versusAI(difficulty, _, _): "vs \(difficulty.displayName)"
        case .passAndPlay: "Pass & Play"
        case let .puzzle(puzzle): puzzle.kind.title
        case .tutorial: "Learn"
        }
    }
}
