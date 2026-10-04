import LudoEngine

/// One step of Learn the game: a small arranged position on the real board, the dice it rolls, and the
/// thing to do. Played against nobody (Black never moves), with Ghana Classic rules, and never saved,
/// so the player's own game is untouched. As in Lelu Oware's lessons: read, do, see why it worked.
struct Lesson: Sendable {
    /// The Learn card it belongs to.
    let chapter: Chapter
    let title: String
    /// What to do.
    let text: String
    /// Said once it is done: why it worked.
    let doneText: String
    /// Red's and Black's tokens, as progress (-1 in the yard).
    let red: [Int]
    var black: [Int] = [-1, -1, -1, -1]
    /// The faces the die shows, in order.
    let dice: [Int]
    /// Done when the turn produces one of these.
    let goal: @Sendable (GameEvent) -> Bool

    enum Chapter: Int, CaseIterable, Sendable {
        case board, moving, ghanaRules

        var title: String {
            switch self {
            case .board: "The board"
            case .moving: "How to move"
            case .ghanaRules: "Special Ghana rules"
            }
        }

        var summary: String {
            switch self {
            case .board: "Move your tokens from home to the centre star."
            case .moving: "Roll, bring tokens out, race around the board, and kick opponents."
            case .ghanaRules: "Kicks, walls, extra rolls, and the black star 6."
            }
        }

        /// The first lesson of this chapter.
        var start: Int { Lesson.all.firstIndex { $0.chapter == self } ?? 0 }
    }

    /// Where a Black token stands to be `ahead` squares in front of a red token at `redProgress`.
    static func black(ahead: Int, of redProgress: Int) -> Int {
        GameState.progress(of: .black, atTrackIndex: (Board.startIndex(.red) + redProgress + ahead) % Board.trackLength)
    }

    static let all: [Lesson] = [
        Lesson(chapter: .board, title: "Your yard",
               text: "Your four red tokens wait in your yard. Only a 6 brings one out onto your start square. Tap the cup to roll.",
               doneText: "Out it comes. A 6 also earns another roll.",
               red: [-1, -1, -1, -1], dice: [6],
               goal: { if case let .moved(.red, move) = $0 { move.kind == .enter } else { false } }),
        Lesson(chapter: .board, title: "Home is the centre",
               text: "Tokens race clockwise round the track, up your red lane, and finish on the centre star. This one is 3 from home: roll and move it in.",
               doneText: "Home! Bring all four home first to win.",
               red: [Board.home - 3, -1, -1, -1], dice: [3],
               goal: { if case .reachedHome(.red, _) = $0 { true } else { false } }),
        Lesson(chapter: .moving, title: "Move by the roll",
               text: "A token moves exactly the number you roll. Roll, then tap your token to move it.",
               doneText: "Four squares on. Every roll is a choice of which token to move.",
               red: [5, -1, -1, -1], dice: [4],
               goal: { if case let .moved(.red, move) = $0 { move.kind == .forward } else { false } }),
        Lesson(chapter: .moving, title: "Kick",
               text: "Land on an opponent and you kick it back to its yard. Black is 3 squares ahead: roll and land on it.",
               doneText: "Kicked! Black's token is back in its yard, and a kick earns you another roll.",
               red: [15, -1, -1, -1], black: [black(ahead: 3, of: 15), -1, -1, -1], dice: [3],
               goal: { if case .kicked(.black, _, _, by: .red) = $0 { true } else { false } }),
        Lesson(chapter: .ghanaRules, title: "Back kick",
               text: "In Ghana you can kick backwards too. Roll a 5, tap your token, and choose the back kick onto Black behind you.",
               doneText: "A back kick: same roll, but backwards onto an opponent.",
               red: [12, -1, -1, -1], black: [black(ahead: -5, of: 12), -1, -1, -1], dice: [5],
               goal: { if case let .moved(.red, move) = $0 { move.kind == .backKick } else { false } }),
        Lesson(chapter: .ghanaRules, title: "A wall",
               text: "Two tokens of one colour on a square make a wall nobody can pass. Black has a wall 3 ahead of you. Roll and see.",
               doneText: "Your 4 would pass the wall, so you can't move. Walls block the whole track.",
               red: [6, -1, -1, -1], black: [black(ahead: 3, of: 6), black(ahead: 3, of: 6), -1, -1], dice: [4],
               goal: { if case .passed(.red) = $0 { true } else { false } }),
        Lesson(chapter: .ghanaRules, title: "The black star 6",
               text: "The 6 shows Ghana's black star. It is simply a 6: it brings a token out or moves one six, then you roll again. Roll it.",
               doneText: "That's Lelu Ludo. Play the computer to practise.",
               red: [20, -1, -1, -1], dice: [6],
               goal: { if case .moved(.red, _) = $0 { true } else { false } }),
    ]
}

/// Where the player is in Learn the game.
struct TutorialProgress: Equatable, Sendable {
    var index: Int
    var outcome: Outcome = .playing

    enum Outcome: Sendable { case playing, done, tryAgain }

    var lesson: Lesson { Lesson.all[index] }
    var isLast: Bool { index == Lesson.all.count - 1 }
}
