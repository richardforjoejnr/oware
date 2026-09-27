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

    private static func pos(_ a: [Int], _ b: [Int], stores: [Int] = [0, 0], rules: RuleSet = .abapa) -> GameState {
        GameState(houses: a + b, stores: stores, sideToMove: .south, rules: rules)
    }

    /// The lesson for the rules chosen in Settings.
    static func steps(for variant: RuleSet.Variant) -> [Step] { variant == .namNam ? namNamSteps : steps }

    /// Nam-Nam: sowing and roaming, fours on each side, feeding, the last four and territory.
    static let namNamSteps: [Step] = {
        // Seeds not on the board sit in the stores, so every lesson is a real 48-seed position.
        func nn(_ a: [Int], _ b: [Int], stores: [Int]? = nil) -> GameState {
            let spare = 48 - (a + b).reduce(0, +)
            return pos(a, b, stores: stores ?? [spare - spare / 2, spare / 2], rules: .namNam)
        }
        return [
            Step(title: "Akwaaba",
                 prompt: "Welcome to Nam-Nam, \"to roam\". Two rows of six houses, four seeds in each. You start with the bottom row, A1 to A6.",
                 position: nil, requiredMove: nil, afterText: nil),
            Step(title: "Sowing",
                 prompt: "Pick up all the seeds from a house and drop one in each house after it, going anticlockwise. A3 has two seeds. Play it.",
                 position: nn([0, 0, 2, 0, 0, 0], [0, 0, 0, 1, 1, 1]), requiredMove: Move(notation: "A3"),
                 afterText: "Your last seed fell into an empty house, so your turn ended."),
            Step(title: "Roaming",
                 prompt: "If your last seed lands among other seeds, scoop them all up and keep sowing. Play A3 again and watch the seeds roam.",
                 position: nn([0, 0, 2, 0, 2, 0], [0, 0, 0, 1, 1, 1]), requiredMove: Move(notation: "A3"),
                 afterText: "A5 already held seeds, so you picked them up and carried on until a seed landed in an empty house."),
            Step(title: "Making four",
                 prompt: "Any house on your side that reaches four seeds is yours, even in the middle of sowing. Play A1: it passes A2, which holds three.",
                 position: nn([2, 3, 0, 0, 0, 0], [1, 1, 1, 1, 1, 2]), requiredMove: Move(notation: "A1"),
                 afterText: "A2 made four and went straight to your store."),
            Step(title: "Four on their side",
                 prompt: "A house on the other side is yours only if your last seed makes it four. B1 holds three. Play A6.",
                 position: nn([0, 0, 0, 0, 0, 1], [3, 1, 1, 1, 1, 2]), requiredMove: Move(notation: "A6"),
                 afterText: "Your last seed made four in B1, so you took it."),
            Step(title: "Careful",
                 prompt: "If you make four on their side with a seed that is not your last, the four is theirs. Play A6 and see.",
                 position: nn([0, 0, 0, 0, 0, 2], [3, 0, 1, 1, 1, 1]), requiredMove: Move(notation: "A6"),
                 afterText: "B1 reached four before your last seed, so it went to the other player."),
            Step(title: "Feeding",
                 prompt: "If the other side has no seeds, you must give them some when you can. Only A6 reaches across. Play it.",
                 position: nn([1, 0, 0, 0, 0, 1], [0, 0, 0, 0, 0, 0], stores: [23, 23]), requiredMove: Move(notation: "A6"),
                 afterText: "If nobody can be fed, the round ends and each keeps the seeds on their own side."),
            Step(title: "The last four",
                 prompt: "When only eight seeds are left, whoever takes the next four also takes the last four, and the round ends. Play A1.",
                 position: nn([1, 3, 0, 0, 0, 0], [0, 0, 0, 0, 4, 0], stores: [20, 20]), requiredMove: Move(notation: "A1"),
                 afterText: "You finished the round with 28 seeds: seven houses' worth. Next round, one of their houses is yours."),
            Step(title: "Winning",
                 prompt: "Each round, the seeds you win fill houses four at a time; win more than 24 and you take houses from the other side. Hold all twelve to win. Medaase — now play.",
                 position: nil, requiredMove: nil, afterText: nil),
        ]
    }()

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
