/// A game of Ludo: where every token is, whose turn it is and the roll waiting to be played.
///
/// A turn is `roll(_:)` then, if any move is legal, `apply(_:)` with one of `legalMoves()`. The roll
/// comes from outside (the app's dice, a test's script), so games replay exactly. A 6, and with the
/// default rules a kick or a token reaching home, gives the same player another roll.
public struct GameState: Sendable, Codable, Hashable {
    public private(set) var rules: RuleSet
    /// The colours playing, in turn order (clockwise).
    public let players: [PlayerColor]
    /// Each colour's four tokens, as progress from its own start (-1 yard … 56 home).
    public private(set) var progress: [[Int]]
    public private(set) var toMove: PlayerColor
    /// The roll waiting to be played, if any.
    public private(set) var pendingRoll: Int?
    /// Sixes rolled in a row this turn.
    public private(set) var sixesInARow = 0
    public private(set) var winner: PlayerColor?
    /// Where the tokens stood when this turn began, for the three-sixes rule.
    private var turnStart: [[Int]]

    public init(players: [PlayerColor] = PlayerColor.allCases, rules: RuleSet = .ghana, first: PlayerColor? = nil) {
        precondition((2...4).contains(players.count) && Set(players).count == players.count, "2 to 4 different colours")
        let seated = PlayerColor.allCases.filter(players.contains)   // clockwise, whatever order they were given in
        self.players = seated
        self.rules = rules
        progress = Array(repeating: Array(repeating: Board.yard, count: Board.tokensPerPlayer), count: 4)
        toMove = first.flatMap { seated.contains($0) ? $0 : nil } ?? seated[0]
        turnStart = progress
    }

    /// Puts tokens where a test wants them (progress per colour); the turn starts afresh from there.
    mutating func place(_ placed: [PlayerColor: [Int]]) {
        for (color, tokens) in placed {
            precondition(tokens.count == Board.tokensPerPlayer && tokens.allSatisfy { (Board.yard...Board.home).contains($0) })
            progress[color.rawValue] = tokens
        }
        turnStart = progress
    }

    public var isOver: Bool { winner != nil }

    public func tokens(of color: PlayerColor) -> [Int] { progress[color.rawValue] }

    /// Tokens home for a colour.
    public func homeCount(_ color: PlayerColor) -> Int { tokens(of: color).filter { $0 == Board.home }.count }

    // MARK: - Turn

    /// Roll the die for the player to move. A third 6 in a row (with that rule) undoes the turn; a roll
    /// with no legal move passes (or, for a 6, rolls again).
    @discardableResult
    public mutating func roll(_ value: Int) -> [GameEvent] {
        precondition((1...6).contains(value), "a die has six faces")
        precondition(pendingRoll == nil && winner == nil, "play the last roll first")
        var events: [GameEvent] = [.rolled(toMove, value)]
        sixesInARow = value == 6 ? sixesInARow + 1 : 0
        if rules.threeSixesForfeit && sixesInARow == 3 {
            progress = turnStart
            events.append(.threeSixes(toMove))
            endTurn(&events)
            return events
        }
        pendingRoll = value
        if legalMoves().isEmpty {
            pendingRoll = nil
            events.append(.passed(toMove))
            if value == 6 { events.append(.rollAgain(toMove)) } else { endTurn(&events) }
        }
        return events
    }

    /// Every move the pending roll allows the player to move.
    public func legalMoves() -> [Move] {
        guard let r = pendingRoll, winner == nil else { return [] }
        let me = toMove
        var moves: [Move] = []
        for (i, p) in tokens(of: me).enumerated() {
            if p == Board.yard {
                if rules.entryRolls.contains(r), canLand(me, at: Board.startIndex(me)) {
                    moves.append(Move(token: i, kind: .enter, from: p, to: 0))
                }
                continue
            }
            guard p < Board.home else { continue }
            // Forwards.
            let q = p + r
            if q <= Board.home, pathClear(me, from: p, to: q), landingOK(me, progress: q) {
                moves.append(Move(token: i, kind: .forward, from: p, to: q))
            }
            // Back kick: onto an opponent exactly the roll behind, never back past the start.
            if rules.backKick, p <= Board.lastTrackProgress, r <= p {
                let target = Board.trackIndex(me, progress: p - r)
                if !kickable(at: target, by: me).isEmpty, pathClear(me, from: p - r, to: p) {
                    moves.append(Move(token: i, kind: .backKick, from: p, to: p - r))
                }
            }
        }
        return moves
    }

    /// Play one of `legalMoves()`.
    @discardableResult
    public mutating func apply(_ move: Move) throws -> [GameEvent] {
        guard legalMoves().contains(move), let r = pendingRoll else { throw MoveError.illegal }
        let me = toMove
        var events: [GameEvent] = [.moved(me, move)]
        progress[me.rawValue][move.token] = move.to
        var earned = false
        if move.to <= Board.lastTrackProgress {
            let at = Board.trackIndex(me, progress: move.to)
            for (color, token) in kickable(at: at, by: me) {
                progress[color.rawValue][token] = Board.yard
                events.append(.kicked(color, token: token, at: at, by: me))
                earned = true
            }
        }
        if move.to == Board.home {
            events.append(.reachedHome(me, token: move.token))
            earned = true
        }
        pendingRoll = nil
        if homeCount(me) == Board.tokensPerPlayer {
            winner = me
            events.append(.won(me))
            return events
        }
        if r == 6 || (rules.kickOrHomeEarnsRoll && earned) {
            events.append(.rollAgain(me))
        } else {
            endTurn(&events)
        }
        return events
    }

    public enum MoveError: Error, Sendable { case illegal }

    // MARK: - Saves

    private enum CodingKeys: String, CodingKey {
        case rules, players, progress, toMove, pendingRoll, sixesInARow, winner, turnStart
    }

    /// Throws `DecodingError.dataCorrupted` for a damaged save rather than loading a game the rules
    /// would trap on.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decode(RuleSet.self, forKey: .rules)
        players = try c.decode([PlayerColor].self, forKey: .players)
        progress = try c.decode([[Int]].self, forKey: .progress)
        toMove = try c.decode(PlayerColor.self, forKey: .toMove)
        pendingRoll = try c.decodeIfPresent(Int.self, forKey: .pendingRoll)
        sixesInARow = try c.decode(Int.self, forKey: .sixesInARow)
        winner = try c.decodeIfPresent(PlayerColor.self, forKey: .winner)
        turnStart = try c.decode([[Int]].self, forKey: .turnStart)

        func check(_ ok: Bool, _ key: CodingKeys, _ what: String) throws {
            guard ok else { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: what) }
        }
        let tokensOK = { (p: [[Int]]) in p.count == 4 && p.allSatisfy { $0.count == Board.tokensPerPlayer && $0.allSatisfy { (Board.yard...Board.home).contains($0) } } }
        try check((2...4).contains(players.count) && Set(players).count == players.count
                  && players == PlayerColor.allCases.filter(players.contains), .players, "2 to 4 colours, clockwise")
        try check(tokensOK(progress), .progress, "four colours of four tokens, each -1…56")
        try check(tokensOK(turnStart), .turnStart, "four colours of four tokens, each -1…56")
        try check(players.contains(toMove), .toMove, "the player to move is playing")
        try check(pendingRoll.map { (1...6).contains($0) } ?? true, .pendingRoll, "a roll is 1…6")
        // With the three-sixes rule a third 6 ends the turn, so at most two are ever carried.
        try check(sixesInARow >= 0 && (!rules.threeSixesForfeit || sixesInARow <= 2), .sixesInARow, "sixes in a row within the rules")
        try check(winner.map { w in players.contains(w) && progress[w.rawValue].allSatisfy { $0 == Board.home } } ?? true,
                  .winner, "a winner has every token home")
        try check(rules.entryRolls.allSatisfy { (1...6).contains($0) } && !rules.entryRolls.isEmpty, .rules, "entry rolls are faces of a die")
    }

    private mutating func endTurn(_ events: inout [GameEvent]) {
        let i = players.firstIndex(of: toMove)!
        toMove = players[(i + 1) % players.count]
        sixesInARow = 0
        pendingRoll = nil
        turnStart = progress
        events.append(.turn(toMove))
    }

    // MARK: - Squares

    /// Tokens of each colour on a track square.
    public func occupants(at trackIndex: Int) -> [(color: PlayerColor, token: Int)] {
        var found: [(PlayerColor, Int)] = []
        for color in players {
            for (i, p) in tokens(of: color).enumerated() where (0...Board.lastTrackProgress).contains(p) {
                if Board.trackIndex(color, progress: p) == trackIndex { found.append((color, i)) }
            }
        }
        return found
    }

    public func isSafe(_ trackIndex: Int) -> Bool {
        (rules.startSquaresSafe && PlayerColor.allCases.contains { Board.startIndex($0) == trackIndex })
            || (rules.starSquaresSafe && Board.starIndices.contains(trackIndex))
    }

    /// Two or more tokens of one colour other than `mover` on the square.
    private func stack(at trackIndex: Int, against mover: PlayerColor) -> Bool {
        let others = occupants(at: trackIndex).filter { $0.color != mover }
        return Dictionary(grouping: others, by: \.color).values.contains { $0.count >= 2 }
    }

    /// The opponent tokens a token of `mover` landing here would kick: lone tokens, off safe squares,
    /// and none if they stand as a stack.
    private func kickable(at trackIndex: Int, by mover: PlayerColor) -> [(color: PlayerColor, token: Int)] {
        guard !isSafe(trackIndex) else { return [] }
        let others = occupants(at: trackIndex).filter { $0.color != mover }
        if rules.stacking != .notAllowed && stack(at: trackIndex, against: mover) { return [] }
        return others
    }

    /// Whether a token of `mover` may end its move on this track square.
    private func canLand(_ mover: PlayerColor, at trackIndex: Int) -> Bool {
        let here = occupants(at: trackIndex)
        if rules.stacking == .notAllowed && here.contains(where: { $0.color == mover }) { return false }
        // An opponent stack cannot be landed on (a wall, or a stack that cannot be kicked).
        if rules.stacking != .notAllowed && stack(at: trackIndex, against: mover) { return false }
        return true
    }

    private func landingOK(_ mover: PlayerColor, progress q: Int) -> Bool {
        if q <= Board.lastTrackProgress { return canLand(mover, at: Board.trackIndex(mover, progress: q)) }
        if q == Board.home { return true }
        // The home lane is private; only the one-token-per-square rule applies there.
        return !(rules.stacking == .notAllowed && tokens(of: mover).contains(q))
    }

    /// No opponent wall strictly between two progresses on the track (walls only with `.wall`).
    private func pathClear(_ mover: PlayerColor, from a: Int, to b: Int) -> Bool {
        guard rules.stacking == .wall, b - a > 1 else { return true }
        for p in (a + 1)..<b where p <= Board.lastTrackProgress {
            if stack(at: Board.trackIndex(mover, progress: p), against: mover) { return false }
        }
        return true
    }
}
