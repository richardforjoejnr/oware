/// House rules. Ludo is played many ways in Ghana; these are the switches, with the owner's defaults
/// (2026-10-03). The core is always on: a 6 to leave the yard, a 6 rolls again, landing on an
/// opponent kicks it home, the home lane is private, and home needs the exact roll.
public struct RuleSet: Sendable, Codable, Hashable {
    /// What two or more of your own tokens on one track square mean.
    public enum Stacking: String, Sendable, Codable, CaseIterable {
        /// You may not end a move on your own token (the Ghana Ludo rule of one token per square).
        case notAllowed
        /// A wall: no opponent may pass or land on it (Masters of Games' "block").
        case wall
        /// Safe: it cannot be kicked, but others may pass it (another Ghana ruleset).
        case safe
    }

    /// Kicking an opponent home, or bringing a token home, earns another roll.
    public var kickOrHomeEarnsRoll: Bool
    /// A third 6 in a row ends the turn and undoes everything played in it.
    public var threeSixesForfeit: Bool
    public var stacking: Stacking
    /// Back kick: if an opponent is exactly the roll behind one of your tokens on the track, that
    /// token may move back onto it and kick it home instead of moving forwards. A Ghanaian rule.
    public var backKick: Bool
    /// Your own start square is safe: nobody can be kicked there.
    public var startSquaresSafe: Bool
    /// The four star squares half-way along each arm are safe.
    public var starSquaresSafe: Bool
    /// Rolls that bring a token out of the yard (6; a gentler game uses 1 and 6).
    public var entryRolls: Set<Int>
    /// Home kick: an opponent in their own home lane is not safe. With the exact roll a token may turn
    /// into that lane and kick them; it then walks back out the way it came on later turns.
    public var homeKick: Bool
    /// Side kicks: after a legal move forwards (or backwards), a token directly across a home lane
    /// from an opponent, with the lane square between them clear, may jump across and kick them.
    public var forwardSideKick: Bool
    public var backSideKick: Bool
    /// Labourer: reserved. No behaviour until the owner defines the Ghana house rule exactly.
    public var labourerEnabled: Bool

    public init(kickOrHomeEarnsRoll: Bool = true, threeSixesForfeit: Bool = true, stacking: Stacking = .wall,
                backKick: Bool = true, startSquaresSafe: Bool = false, starSquaresSafe: Bool = false,
                entryRolls: Set<Int> = [6], homeKick: Bool = true, forwardSideKick: Bool = true,
                backSideKick: Bool = true, labourerEnabled: Bool = false) {
        self.kickOrHomeEarnsRoll = kickOrHomeEarnsRoll
        self.threeSixesForfeit = threeSixesForfeit
        self.stacking = stacking
        self.backKick = backKick
        self.startSquaresSafe = startSquaresSafe
        self.starSquaresSafe = starSquaresSafe
        self.entryRolls = entryRolls
        self.homeKick = homeKick
        self.forwardSideKick = forwardSideKick
        self.backSideKick = backSideKick
        self.labourerEnabled = labourerEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case kickOrHomeEarnsRoll, threeSixesForfeit, stacking, backKick, startSquaresSafe, starSquaresSafe, entryRolls
        case homeKick, forwardSideKick, backSideKick, labourerEnabled
    }

    /// Saves from before a rule existed load with that rule off.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kickOrHomeEarnsRoll = try c.decode(Bool.self, forKey: .kickOrHomeEarnsRoll)
        threeSixesForfeit = try c.decode(Bool.self, forKey: .threeSixesForfeit)
        stacking = try c.decode(Stacking.self, forKey: .stacking)
        backKick = try c.decode(Bool.self, forKey: .backKick)
        startSquaresSafe = try c.decode(Bool.self, forKey: .startSquaresSafe)
        starSquaresSafe = try c.decode(Bool.self, forKey: .starSquaresSafe)
        entryRolls = try c.decode(Set<Int>.self, forKey: .entryRolls)
        homeKick = try c.decodeIfPresent(Bool.self, forKey: .homeKick) ?? false
        forwardSideKick = try c.decodeIfPresent(Bool.self, forKey: .forwardSideKick) ?? false
        backSideKick = try c.decodeIfPresent(Bool.self, forKey: .backSideKick) ?? false
        labourerEnabled = try c.decodeIfPresent(Bool.self, forKey: .labourerEnabled) ?? false
    }

    /// Ghana Classic, Lelu Ludo's defaults (owner, 2026-10-03): forward, back, forward side, back side
    /// and home kicks on; a 6 rolls again; home needs the exact roll; Labourer off until it is defined.
    public static let ghanaClassic = RuleSet()
    public static let ghana = ghanaClassic
    /// Plain Ludo as most printed rule sheets give it, for tests and comparison.
    public static let classic = RuleSet(kickOrHomeEarnsRoll: false, threeSixesForfeit: false, stacking: .wall, backKick: false,
                                        homeKick: false, forwardSideKick: false, backSideKick: false)
}
