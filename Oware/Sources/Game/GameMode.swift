import OwareEngine
import OwareAI

/// Who is playing whom.
enum GameMode: Codable, Hashable, Sendable {
    case versusAI(difficulty: Difficulty, personality: Personality, humanPlays: Player)
    case passAndPlay

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

    var title: String {
        switch self {
        case let .versusAI(difficulty, _, _): "vs \(difficulty.displayName)"
        case .passAndPlay: "Pass & Play"
        }
    }
}
