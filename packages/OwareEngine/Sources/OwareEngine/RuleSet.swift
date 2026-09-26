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

    /// Which game is being played.
    public enum Variant: String, Sendable, Codable, CaseIterable {
        /// Tournament Oware: sow once, capture opponent houses brought to 2 or 3, first to 25 wins.
        case abapa
        /// Nam-Nam ("to roam"): relay sowing — if the last seed lands in a house that already held
        /// seeds, scoop it up and carry on; captures are made by bringing a house to four (your own
        /// territory at any point, the opponent's only with your last seed); when a capture leaves
        /// four seeds on the board the capturer takes them and the round ends; seeds won become
        /// territory for the next round; the game ends when one player owns all twelve houses.
        case namNam
    }

    public var variant: Variant
    public var grandSlam: GrandSlamRule
    /// If the opponent has no seeds, the mover must play a move that gives them seeds when possible.
    public var mustFeed: Bool
    /// Seeds needed to win outright (25 of 48).
    public var winningSeeds: Int
    /// When the same position (houses + side to move) occurs this many times, the game is
    /// declared cyclic and each player keeps the seeds on their own side.
    public var repetitionLimit: Int

    /// Nam-Nam only: rounds are capped so a perfectly balanced pair cannot play for ever.
    public var maxRounds: Int

    public init(
        variant: Variant = .abapa,
        grandSlam: GrandSlamRule = .forfeitCapture,
        mustFeed: Bool = true,
        winningSeeds: Int = 25,
        repetitionLimit: Int = 3,
        maxRounds: Int = 20
    ) {
        self.variant = variant
        self.maxRounds = maxRounds
        self.grandSlam = grandSlam
        self.mustFeed = mustFeed
        self.winningSeeds = winningSeeds
        self.repetitionLimit = repetitionLimit
    }

    /// Abapa — "the proper version" used for adult and competition play.
    public static let abapa = RuleSet()
    /// The children's game of Ghana's coast and the Caribbean.
    public static let namNam = RuleSet(variant: .namNam)

    /// Older saves have no `variant` / `maxRounds` keys: treat them as Abapa.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        variant = try c.decodeIfPresent(Variant.self, forKey: .variant) ?? .abapa
        maxRounds = try c.decodeIfPresent(Int.self, forKey: .maxRounds) ?? 20
        grandSlam = try c.decode(GrandSlamRule.self, forKey: .grandSlam)
        mustFeed = try c.decode(Bool.self, forKey: .mustFeed)
        winningSeeds = try c.decode(Int.self, forKey: .winningSeeds)
        repetitionLimit = try c.decode(Int.self, forKey: .repetitionLimit)
    }
}
