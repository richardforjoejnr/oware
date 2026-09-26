/// Configurable rule variants. The default is Abapa, the tournament version of Oware.
public struct RuleSet: Sendable, Codable, Hashable {
    /// What happens when a move would capture *every* seed on the opponent's side.
    public enum GrandSlamRule: String, Sendable, Codable, CaseIterable {
        /// The move is legal but the capture is forfeited (international tournament rule; default).
        case forfeitCapture
        /// The move is not allowed at all.
        case illegalMove
        /// The capture stands and the game ends; the mover also keeps the seeds on their own side.
        case captureEndsGame
    }

    public var grandSlam: GrandSlamRule
    /// If the opponent has no seeds, the mover must play a move that gives them seeds when possible.
    public var mustFeed: Bool
    /// Seeds needed to win outright (25 of 48).
    public var winningSeeds: Int
    /// When the same position (houses + side to move) occurs this many times, the game is
    /// declared cyclic and each player keeps the seeds on their own side.
    public var repetitionLimit: Int

    public init(
        grandSlam: GrandSlamRule = .forfeitCapture,
        mustFeed: Bool = true,
        winningSeeds: Int = 25,
        repetitionLimit: Int = 3
    ) {
        self.grandSlam = grandSlam
        self.mustFeed = mustFeed
        self.winningSeeds = winningSeeds
        self.repetitionLimit = repetitionLimit
    }

    /// Abapa — "the proper version" used for adult and competition play.
    public static let abapa = RuleSet()
}
