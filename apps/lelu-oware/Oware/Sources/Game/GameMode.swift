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
    /// A Journey match against `Journey.chapters[chapter].opponents[opponent]`; the human is south.
    case journey(chapter: Int, opponent: Int)

    var journeyOpponent: Journey.Opponent? {
        if case let .journey(c, o) = self { return Journey.opponent(chapter: c, index: o) }
        return nil
    }

    var aiSide: Player? {
        switch self {
        case let .versusAI(_, _, human): human.opponent
        case .journey: .north
        default: nil
        }
    }

    var aiPlayer: AIPlayer? {
        switch self {
        case let .versusAI(difficulty, personality, _):
            AIPlayer(difficulty: difficulty, personality: personality)
        case .journey:
            journeyOpponent.map { AIPlayer(difficulty: $0.difficulty, personality: $0.personality) }
        default: nil
        }
    }

    /// Modes that are ordinary games worth saving and resuming.
    var isResumable: Bool {
        switch self {
        case .versusAI, .passAndPlay, .journey: true
        case .puzzle, .tutorial: false
        }
    }

    var title: String {
        switch self {
        case let .versusAI(difficulty, _, _): "vs \(difficulty.displayName)"
        case .passAndPlay: "Pass & Play"
        case let .puzzle(puzzle): puzzle.kind.title
        case .tutorial: "Learn"
        case .journey: journeyOpponent.map { "\($0.name) · \($0.role)" } ?? "Journey"
        }
    }
}
