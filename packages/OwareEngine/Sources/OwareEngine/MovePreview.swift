/// What a move would do, without playing it. Used for the long-press landing preview.
public struct MovePreview: Sendable, Hashable {
    public let move: Move
    /// Houses that receive a seed, in sowing order (repeats on laps).
    public let path: [Int]
    /// Where the last seed lands.
    public let landingHouse: Int
    /// Opponent houses that would be captured (empty if none, or if the capture is forfeited).
    public let captures: [Int]
    /// Seeds that would be captured in total.
    public let capturedSeeds: Int
    /// True when the move would take every opponent seed and the rules forfeit that capture.
    public let grandSlamForfeited: Bool
    /// Board after sowing and capturing.
    public let resultingHouses: [Int]
}

extension GameState {
    /// Preview a legal-or-not move from a non-empty house. Nil if the house is empty or the game is over.
    public func preview(_ move: Move) -> MovePreview? {
        guard !isOver, houses[move.absoluteIndex] > 0, move.player == sideToMove,
              territory[move.absoluteIndex] == move.player else { return nil }
        if rules.variant == .namNam {
            let sim = simulateNamNam(move)
            let path = sim.steps.compactMap { step -> Int? in
                if case let .dropped(house, _) = step { return house }
                return nil
            }
            var captures: [Int] = []
            var total = 0
            for step in sim.steps {
                if case let .captured(house, seeds, by) = step, by == move.player {
                    captures.append(house)
                    total += seeds
                }
            }
            return MovePreview(move: move, path: path, landingHouse: sim.lastHouse, captures: captures,
                               capturedSeeds: total, grandSlamForfeited: false, resultingHouses: sim.houses)
        }
        let sowing = simulateSowing(move)
        let path = sowing.steps.compactMap { step -> Int? in
            if case let .dropped(house, _) = step { return house }
            return nil
        }
        let grandSlam = Self.isGrandSlam(sowing, in: self)
        let forfeited = grandSlam && rules.grandSlam == .forfeitCapture
        let captures = forfeited ? [] : sowing.captured
        var result = sowing.houses
        var total = 0
        for house in captures {
            total += result[house]
            result[house] = 0
        }
        return MovePreview(
            move: move,
            path: path,
            landingHouse: sowing.lastHouse,
            captures: captures,
            capturedSeeds: total,
            grandSlamForfeited: forfeited,
            resultingHouses: result
        )
    }
}
