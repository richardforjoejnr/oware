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
    /// A game on two phones; the other phone's player moves `remoteSide`.
    case remote(RemoteGame)

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

    var remoteGame: RemoteGame? {
        if case let .remote(game) = self { return game }
        return nil
    }

    /// The side the other phone's player moves.
    var remoteSide: Player? { remoteGame?.mySide.opponent }

    /// The side nobody on this phone moves: the computer's or the other phone's.
    var otherSide: Player? { aiSide ?? remoteSide }

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
        // Not resumable after the app is closed, in v1 (NEARBY_PLAY.md, still to decide).
        case .puzzle, .tutorial, .remote: false
        }
    }

    var title: String {
        switch self {
        case let .versusAI(difficulty, _, _): "vs \(difficulty.displayName)"
        case .passAndPlay: "Pass & Play"
        case let .puzzle(puzzle): puzzle.kind.title
        case .tutorial: "Learn"
        case .journey: journeyOpponent.map { "\($0.name) · \($0.role)" } ?? "Journey"
        case let .remote(game): "vs \(game.opponentName)"
        }
    }
}
