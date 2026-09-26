import OwareEngine

/// Weights for the static evaluation. Personalities are just different weight sets.
public struct EvaluationWeights: Sendable, Codable, Hashable {
    /// Per captured-seed difference. Everything else is relative to this.
    public var store: Int
    /// Per seed on own side minus opponent's side.
    public var material: Int
    /// Per non-empty house difference (a proxy for mobility).
    public var mobility: Int
    /// Per opponent house holding 1 or 2 seeds (capturable targets) minus own such houses.
    public var vulnerability: Int
    /// Per house with 12+ seeds (an accumulating "kroo") difference.
    public var kroo: Int
    /// Per empty house on the opponent's side minus own side.
    public var emptyHouses: Int

    public init(store: Int = 100, material: Int = 2, mobility: Int = 4, vulnerability: Int = 8, kroo: Int = 12, emptyHouses: Int = 3) {
        self.store = store
        self.material = material
        self.mobility = mobility
        self.vulnerability = vulnerability
        self.kroo = kroo
        self.emptyHouses = emptyHouses
    }

    public static let balanced = EvaluationWeights()
}

/// A named play style. Journey opponents each have one.
public struct Personality: Sendable, Codable, Hashable {
    public var name: String
    public var weights: EvaluationWeights

    public init(name: String, weights: EvaluationWeights) {
        self.name = name
        self.weights = weights
    }

    public static let balanced = Personality(name: "Balanced", weights: .balanced)
    /// Chases captures and targets weak houses.
    public static let aggressive = Personality(name: "Aggressive", weights: EvaluationWeights(store: 110, material: 1, mobility: 2, vulnerability: 16, kroo: 6, emptyHouses: 2))
    /// Builds a big house and waits.
    public static let hoarder = Personality(name: "Hoarder", weights: EvaluationWeights(store: 90, material: 5, mobility: 2, vulnerability: 5, kroo: 30, emptyHouses: 1))
    /// Keeps its own houses safe above all.
    public static let cautious = Personality(name: "Cautious", weights: EvaluationWeights(store: 100, material: 3, mobility: 6, vulnerability: 4, kroo: 8, emptyHouses: 6))
    /// Values options and tempo.
    public static let trickster = Personality(name: "Trickster", weights: EvaluationWeights(store: 95, material: 1, mobility: 12, vulnerability: 10, kroo: 4, emptyHouses: 8))

    public static let all: [Personality] = [.balanced, .aggressive, .hoarder, .cautious, .trickster]
}

public enum Evaluation {
    public static let winScore = 100_000

    /// Score of `state` from `player`'s point of view. Terminal positions are exact.
    public static func score(_ state: GameState, for player: Player, weights: EvaluationWeights, ply: Int = 0) -> Int {
        if let outcome = state.outcome {
            switch outcome {
            case let .win(winner, _):
                return winner == player ? winScore - ply : -winScore + ply
            case .draw:
                return 0
            }
        }
        let opponent = player.opponent
        var score = weights.store * (state.store(of: player) - state.store(of: opponent))

        var material = 0, mobility = 0, vulnerability = 0, kroo = 0, empty = 0
        for house in player.houseRange {
            let n = state.houses[house]
            material += n
            if n > 0 { mobility += 1 } else { empty -= 1 }
            if n == 1 || n == 2 { vulnerability -= 1 }
            if n >= 12 { kroo += 1 }
        }
        for house in opponent.houseRange {
            let n = state.houses[house]
            material -= n
            if n > 0 { mobility -= 1 } else { empty += 1 }
            if n == 1 || n == 2 { vulnerability += 1 }
            if n >= 12 { kroo -= 1 }
        }
        score += weights.material * material
        score += weights.mobility * mobility
        score += weights.vulnerability * vulnerability
        score += weights.kroo * kroo
        score += weights.emptyHouses * empty
        return score
    }
}
