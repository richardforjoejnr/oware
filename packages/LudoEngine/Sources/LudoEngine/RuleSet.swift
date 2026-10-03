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

    public init(kickOrHomeEarnsRoll: Bool = true, threeSixesForfeit: Bool = true, stacking: Stacking = .wall,
                backKick: Bool = true, startSquaresSafe: Bool = false, starSquaresSafe: Bool = false,
                entryRolls: Set<Int> = [6]) {
        self.kickOrHomeEarnsRoll = kickOrHomeEarnsRoll
        self.threeSixesForfeit = threeSixesForfeit
        self.stacking = stacking
        self.backKick = backKick
        self.startSquaresSafe = startSquaresSafe
        self.starSquaresSafe = starSquaresSafe
        self.entryRolls = entryRolls
    }

    /// Lelu Ludo's defaults.
    public static let ghana = RuleSet()
    /// Plain Ludo as most printed rule sheets give it, for tests and comparison.
    public static let classic = RuleSet(kickOrHomeEarnsRoll: false, threeSixesForfeit: false, stacking: .wall, backKick: false)
}
