import OwareEngine

/// "Learn from Nana": a short guided lesson. Each step shows a position, a prompt, and
/// (optionally) the one move the learner must make before continuing.
enum Tutorial {
    struct Step: Sendable, Hashable {
        let title: String
        let prompt: String
        /// Position to show; nil means the standard opening.
        let position: GameState?
        /// The move the learner must make; nil for read-only steps.
        let requiredMove: Move?
        /// Shown after the required move is made.
        let afterText: String?
    }

    private static func pos(_ a: [Int], _ b: [Int], stores: [Int] = [0, 0]) -> GameState {
        GameState(houses: a + b, stores: stores, sideToMove: .south)
    }

    static let steps: [Step] = [
        Step(title: "Akwaaba",
             prompt: "Welcome. Two rows of six houses, four seeds in each. You play the bottom row, A1 to A6.",
             position: nil, requiredMove: nil, afterText: nil),
        Step(title: "Sowing",
             prompt: "Pick up all the seeds from a house and drop one in each house after it, going round to the right. Try A3.",
             position: nil, requiredMove: Move(notation: "A3"), afterText: "Four seeds went into A4, A5, A6 and B1. Sowing always runs anticlockwise round the board."),
        Step(title: "Capturing",
             prompt: "If your last seed lands in the other row and makes that house 2 or 3, you capture it. A6 holds one seed and B1 holds two. Play A6.",
             position: pos([4, 4, 4, 4, 4, 1], [2, 4, 4, 4, 4, 4]), requiredMove: Move(notation: "A6"),
             afterText: "B1 became 3 and the seeds went to your store. Only 2s and 3s are captured, and only when the last seed makes them."),
        Step(title: "Chains",
             prompt: "Captures walk backwards. A6 has four seeds: they will make B1, B2, B3 and B4 all 2s and 3s. Play A6.",
             position: pos([4, 4, 5, 4, 1, 4], [1, 2, 2, 1, 4, 4]), requiredMove: Move(notation: "A6"),
             afterText: "Ten seeds in one move. The chain stops at the first house that is not a 2 or 3."),
        Step(title: "Not everything",
             prompt: "You may never take all the other side's seeds. Here A6 would capture everything, so the capture is forfeited. Play it and watch.",
             position: pos([4, 4, 5, 4, 1, 3], [1, 1, 2, 0, 0, 0]), requiredMove: Move(notation: "A6"),
             afterText: "The seeds stayed. The other player must always be left something to play."),
        Step(title: "Feeding",
             prompt: "If the other row is empty, you must give them seeds when you can. Only A6 reaches across here. Play it.",
             position: pos([1, 0, 0, 0, 0, 1], [0, 0, 0, 0, 0, 0], stores: [22, 24]), requiredMove: Move(notation: "A6"),
             afterText: "Oware is generous by rule. A player who cannot feed keeps their own seeds and the game ends."),
        Step(title: "Winning",
             prompt: "The first to 25 seeds wins; 24 each is a draw. Medaase — now play.",
             position: nil, requiredMove: nil, afterText: nil),
    ]
}
