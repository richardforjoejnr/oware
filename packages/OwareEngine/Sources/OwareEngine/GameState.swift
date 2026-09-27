/// Pure, UI-independent Oware rules engine: Abapa (tournament) and Nam-Nam (relay, fours, rounds).
///
/// Houses 0–5 are the south row (A1–A6), 6–11 the north row (B1–B6), indexed counter-clockwise.
/// Under Abapa each player owns their row. Under Nam-Nam ownership is `territory`, which moves
/// between rounds. The board always holds 48 seeds across houses and stores.
public struct GameState: Sendable, Hashable, Codable {
    public static let houseCount = 12
    public static let seedsPerHouse = 4
    public static let totalSeeds = houseCount * seedsPerHouse

    public var houses: [Int]
    public var stores: [Int]
    public var sideToMove: Player
    public var rules: RuleSet
    /// Number of moves played so far (across rounds).
    public var moveNumber: Int
    /// Set once the game has ended.
    public var outcome: GameOutcome?
    /// How many times each position (houses + side to move) has occurred this round; drives cycle detection.
    public var positionCounts: [String: Int]
    public var lastMove: Move?
    /// Owner of each house. Fixed rows under Abapa; changes between Nam-Nam rounds.
    public var territory: [Player]
    /// 1-based round number (always 1 under Abapa).
    public var round: Int
    /// Nam-Nam: who made the most recent capture this round (takes the last four, breaks ties).
    public var lastCapturer: Player?
    /// Nam-Nam: the rounds completed so far.
    public var roundHistory: [RoundResult]

    public static let defaultTerritory: [Player] = (0..<houseCount).map { $0 < 6 ? .south : .north }

    public init(
        houses: [Int],
        stores: [Int] = [0, 0],
        sideToMove: Player = .south,
        rules: RuleSet = .abapa,
        territory: [Player] = GameState.defaultTerritory
    ) {
        precondition(houses.count == Self.houseCount, "Oware has 12 houses")
        precondition(stores.count == 2, "Two players, two stores")
        precondition(territory.count == Self.houseCount, "one owner per house")
        precondition(houses.allSatisfy { $0 >= 0 } && stores.allSatisfy { $0 >= 0 }, "no negative seeds")
        self.houses = houses
        self.stores = stores
        self.sideToMove = sideToMove
        self.rules = rules
        self.moveNumber = 0
        self.outcome = nil
        self.positionCounts = [:]
        self.lastMove = nil
        self.territory = rules.variant == .namNam ? territory : Self.defaultTerritory
        self.round = 1
        self.lastCapturer = nil
        self.roundHistory = []
        self.positionCounts[positionKey] = 1
    }

    /// The standard opening position: four seeds in every house, south to move.
    public static let initial = GameState(houses: Array(repeating: seedsPerHouse, count: houseCount))

    public static func initial(rules: RuleSet) -> GameState {
        GameState(houses: Array(repeating: seedsPerHouse, count: houseCount), rules: rules)
    }

    // MARK: - Codable (older saves lack the Nam-Nam fields)

    private enum CodingKeys: String, CodingKey {
        case houses, stores, sideToMove, rules, moveNumber, outcome, positionCounts, lastMove, territory, round, lastCapturer, roundHistory
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        houses = try c.decode([Int].self, forKey: .houses)
        stores = try c.decode([Int].self, forKey: .stores)
        sideToMove = try c.decode(Player.self, forKey: .sideToMove)
        rules = try c.decode(RuleSet.self, forKey: .rules)
        moveNumber = try c.decode(Int.self, forKey: .moveNumber)
        outcome = try c.decodeIfPresent(GameOutcome.self, forKey: .outcome)
        positionCounts = try c.decode([String: Int].self, forKey: .positionCounts)
        lastMove = try c.decodeIfPresent(Move.self, forKey: .lastMove)
        territory = try c.decodeIfPresent([Player].self, forKey: .territory) ?? Self.defaultTerritory
        round = try c.decodeIfPresent(Int.self, forKey: .round) ?? 1
        lastCapturer = try c.decodeIfPresent(Player.self, forKey: .lastCapturer)
        roundHistory = try c.decodeIfPresent([RoundResult].self, forKey: .roundHistory) ?? []
    }

    // MARK: - Queries

    public var isOver: Bool { outcome != nil }
    public var seedsOnBoard: Int { houses.reduce(0, +) }
    public var totalSeeds: Int { seedsOnBoard + stores.reduce(0, +) }

    public func seeds(in house: Int) -> Int { houses[house] }
    public func store(of player: Player) -> Int { stores[player.rawValue] }

    /// Who owns a house right now.
    public func owner(of house: Int) -> Player { territory[house] }
    /// The houses a player owns, in board order.
    public func houses(of player: Player) -> [Int] { (0..<Self.houseCount).filter { territory[$0] == player } }
    public func seedsOnSide(of player: Player) -> Int { houses(of: player).reduce(0) { $0 + houses[$1] } }
    public func sideIsEmpty(_ player: Player) -> Bool { seedsOnSide(of: player) == 0 }

    /// Compact key for repetition detection and transposition tables.
    public var positionKey: String {
        houses.map(String.init).joined(separator: ",") + "|" + sideToMove.label
    }

    // MARK: - Legal moves

    /// Moves the side to move may play right now, honouring the feeding obligation
    /// and (Abapa, if configured) the illegal-grand-slam rule. Empty when the game is over.
    public func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        let player = sideToMove
        let candidates = houses(of: player)
            .filter { houses[$0] > 0 }
            .map { Move(player: player, absoluteHouse: $0) }

        var moves = candidates
        if rules.mustFeed && sideIsEmpty(player.opponent) {
            let feeding = candidates.filter { sowingReachesOpponent($0) }
            if !feeding.isEmpty { moves = feeding }
            // If no move can feed, every move is "legal" but apply() will end the game instead.
        }
        if rules.variant == .abapa && rules.grandSlam == .illegalMove {
            moves = moves.filter { !Self.isGrandSlam(simulateSowing($0), in: self) }
        }
        return moves
    }

    public func isLegal(_ move: Move) -> Bool { legalMoves().contains(move) }

    /// True if the whole sowing (including relay laps) drops at least one seed on a house the
    /// opponent owns.
    func sowingReachesOpponent(_ move: Move) -> Bool {
        let opponent = move.player.opponent
        let steps = rules.variant == .namNam ? simulateNamNam(move).steps : simulateSowing(move).steps
        return steps.contains { step in
            if case let .dropped(house, _) = step { return territory[house] == opponent }
            return false
        }
    }

    // MARK: - Applying moves

    /// Play a move, returning the events in order. Throws if the move is illegal.
    @discardableResult
    public mutating func apply(_ move: Move) throws -> [MoveEvent] {
        guard !isOver else { throw MoveError.gameIsOver }
        guard move.player == sideToMove else { throw MoveError.notYourTurn }
        guard territory[move.absoluteIndex] == move.player else { throw MoveError.notYourHouse }
        guard houses[move.absoluteIndex] > 0 else { throw MoveError.emptyHouse }

        let mover = move.player
        let opponent = mover.opponent
        let opponentWasEmpty = sideIsEmpty(opponent)

        // Feeding obligation.
        if rules.mustFeed && opponentWasEmpty && !sowingReachesOpponent(move) {
            let anyFeeding = houses(of: mover)
                .map { Move(player: mover, absoluteHouse: $0) }
                .contains { houses[$0.absoluteIndex] > 0 && sowingReachesOpponent($0) }
            if anyFeeding { throw MoveError.mustFeedOpponent }
            // Nobody can be fed: the mover keeps the seeds on their territory and the round/game ends.
            var events: [MoveEvent] = []
            sweep(mover, into: &events)
            if rules.variant == .namNam {
                endRound(events: &events)
            } else {
                finish(reason: .opponentCouldNotBeFed, events: &events)
            }
            return events
        }

        return rules.variant == .namNam ? applyNamNam(move) : try applyAbapa(move)
    }

    /// Non-mutating variant.
    public func applying(_ move: Move) throws -> MoveResult {
        var copy = self
        let events = try copy.apply(move)
        return MoveResult(move: move, events: events, state: copy)
    }

    /// Both players agree the game is going in circles: each keeps their own side.
    public mutating func endByAgreement() -> [MoveEvent] {
        guard !isOver else { return [] }
        var events: [MoveEvent] = []
        sweep(.south, into: &events)
        sweep(.north, into: &events)
        if rules.variant == .namNam {
            endRound(events: &events)
        } else {
            finish(reason: .agreement, events: &events)
        }
        return events
    }

    // MARK: - Abapa

    private mutating func applyAbapa(_ move: Move) throws -> [MoveEvent] {
        let mover = move.player
        let opponent = mover.opponent
        var events: [MoveEvent] = []

        // Sow.
        let origin = move.absoluteIndex
        let sowing = simulateSowing(move)
        if rules.grandSlam == .illegalMove && Self.isGrandSlam(sowing, in: self) {
            throw MoveError.grandSlamNotAllowed
        }
        events.append(.pickUp(house: origin, seeds: houses[origin]))
        houses = sowing.houses
        for step in sowing.steps {
            switch step {
            case let .dropped(house, count): events.append(.sow(house: house, count: count))
            case .skipped: events.append(.skipOrigin(house: origin))
            case .relayed, .captured: break   // Abapa sowing never produces these
            }
        }

        // Capture.
        let captured = sowing.captured
        if !captured.isEmpty {
            let grandSlam = Self.isGrandSlam(sowing, in: self)
            if grandSlam && rules.grandSlam == .forfeitCapture {
                events.append(.grandSlamForfeited(by: mover, houses: captured))
            } else {
                for house in captured {
                    let seeds = houses[house]
                    houses[house] = 0
                    stores[mover.rawValue] += seeds
                    events.append(.capture(house: house, seeds: seeds, by: mover))
                }
                if grandSlam && rules.grandSlam == .captureEndsGame {
                    sweep(mover, into: &events)
                    finish(reason: .grandSlam, events: &events)
                    return events
                }
            }
        }

        // Bookkeeping.
        moveNumber += 1
        lastMove = move
        sideToMove = opponent

        // Terminal checks.
        if stores[mover.rawValue] >= rules.winningSeeds {
            finish(reason: .reachedWinningSeeds, events: &events)
            return events
        }
        if seedsOnBoard == 0 {
            finish(reason: .boardEmpty, events: &events)
            return events
        }
        if legalMoves().isEmpty {
            // The new side to move is stuck. If they have no seeds at all, the last mover takes
            // what is left; otherwise (illegal-grand-slam edge case) each keeps their own side.
            if sideIsEmpty(sideToMove) {
                sweep(mover, into: &events)
            } else {
                sweep(.south, into: &events)
                sweep(.north, into: &events)
            }
            finish(reason: .noLegalMoves, events: &events)
            return events
        }
        let key = positionKey
        positionCounts[key, default: 0] += 1
        if positionCounts[key]! >= rules.repetitionLimit {
            sweep(.south, into: &events)
            sweep(.north, into: &events)
            finish(reason: .repetition, events: &events)
            return events
        }
        return events
    }

    // MARK: - Nam-Nam

    private mutating func applyNamNam(_ move: Move) -> [MoveEvent] {
        let mover = move.player
        let opponent = mover.opponent
        var events: [MoveEvent] = []

        let origin = move.absoluteIndex
        let sim = simulateNamNam(move)
        events.append(.pickUp(house: origin, seeds: houses[origin]))
        houses = sim.houses
        stores = sim.stores
        var lapOrigin = origin
        for step in sim.steps {
            switch step {
            case let .dropped(house, count): events.append(.sow(house: house, count: count))
            case .skipped: events.append(.skipOrigin(house: lapOrigin))
            case let .relayed(house, seeds):
                events.append(.relay(house: house, seeds: seeds))
                lapOrigin = house
            case let .captured(house, seeds, by):
                events.append(.capture(house: house, seeds: seeds, by: by))
                lastCapturer = by
            }
        }

        moveNumber += 1
        lastMove = move

        if seedsOnBoard == 0 {
            endRound(events: &events)
            return events
        }
        // The other player moves next — unless they have nothing to move, in which case the mover
        // must sow again to feed them (or, if that is impossible, the round ends).
        sideToMove = sideIsEmpty(opponent) ? mover : opponent
        if legalMoves().isEmpty || (sideIsEmpty(opponent) && !legalMoves().contains { sowingReachesOpponent($0) }) {
            sweep(sideToMove, into: &events)
            endRound(events: &events)
            return events
        }
        let key = positionKey
        positionCounts[key, default: 0] += 1
        if positionCounts[key]! >= rules.repetitionLimit {
            sweep(.south, into: &events)
            sweep(.north, into: &events)
            endRound(events: &events)
            return events
        }
        return events
    }

    /// Settle a Nam-Nam round: seeds won become houses owned next round; the game ends when one
    /// player owns them all (or the round cap is reached).
    private mutating func endRound(events: inout [MoveEvent]) {
        let south = stores[Player.south.rawValue], north = stores[Player.north.rawValue]
        var southHouses = south / Self.seedsPerHouse
        var northHouses = north / Self.seedsPerHouse
        // Remainders sum to 0 or 4, so at most one house is left over. It goes to the player who
        // won more seeds this round (they can never be level when a house is spare: 24–24 splits
        // evenly), so winning a round never leaves you behind on houses.
        if Self.houseCount - southHouses - northHouses == 1 {
            if south > north { southHouses += 1 } else { northHouses += 1 }
        }
        let result = RoundResult(round: round, southSeeds: south, northSeeds: north, southHouses: southHouses, northHouses: northHouses)
        roundHistory.append(result)
        events.append(.roundOver(result))

        if southHouses == Self.houseCount || northHouses == Self.houseCount {
            outcome = .win(southHouses == Self.houseCount ? .south : .north, .territory)
            events.append(.gameOver(outcome!))
            return
        }
        if round >= rules.maxRounds {
            outcome = southHouses == northHouses ? .draw(.roundLimit) : .win(southHouses > northHouses ? .south : .north, .roundLimit)
            events.append(.gameOver(outcome!))
            return
        }
        // Next round: the new territory is contiguous from A1 anticlockwise; the other player starts.
        territory = (0..<Self.houseCount).map { $0 < southHouses ? .south : .north }
        houses = Array(repeating: Self.seedsPerHouse, count: Self.houseCount)
        stores = [0, 0]
        round += 1
        lastCapturer = nil
        sideToMove = round % 2 == 1 ? .south : .north
        positionCounts = [positionKey: 1]
    }

    // MARK: - Internals

    enum SowStep: Hashable {
        case dropped(house: Int, count: Int)
        case skipped
        case relayed(house: Int, seeds: Int)
        case captured(house: Int, seeds: Int, by: Player)
    }

    struct Sowing: Hashable {
        var houses: [Int]
        var stores: [Int]
        var steps: [SowStep]
        var lastHouse: Int
        /// Abapa: opponent houses captured, in capture order (last-sown house first, walking backwards).
        var captured: [Int]
        var mover: Player
    }

    /// Backstop for relay chains. The real guard is cycle detection in `simulateNamNam`: relay
    /// sowing can loop for ever (about one random game in 160 reaches such a loop).
    static let maxRelayLaps = 500

    /// Abapa: one lap, captures computed but not applied (grand-slam handling happens in apply).
    func simulateSowing(_ move: Move) -> Sowing {
        let origin = move.absoluteIndex
        var board = houses
        var seeds = board[origin]
        board[origin] = 0
        var steps: [SowStep] = []
        var index = origin
        while seeds > 0 {
            index = (index + 1) % Self.houseCount
            if index == origin {
                steps.append(.skipped)
                continue
            }
            board[index] += 1
            seeds -= 1
            steps.append(.dropped(house: index, count: board[index]))
        }

        var captured: [Int] = []
        let opponent = move.player.opponent
        var walk = index
        while walk >= 0 && territory[walk] == opponent && (board[walk] == 2 || board[walk] == 3) {
            captured.append(walk)
            walk -= 1
        }
        return Sowing(houses: board, stores: stores, steps: steps, lastHouse: index, captured: captured, mover: move.player)
    }

    /// Nam-Nam: relay laps with captures on fours applied as they happen, plus the last-four rule.
    func simulateNamNam(_ move: Move) -> Sowing {
        let mover = move.player
        var board = houses
        var stores = self.stores
        var steps: [SowStep] = []
        var origin = move.absoluteIndex
        var seeds = board[origin]
        board[origin] = 0
        var index = origin
        var laps = 0
        var roundSettled = false
        // Relay positions already seen (board + the house about to be lifted). Seeing one again
        // means the sowing would go round for ever, so the turn ends there instead.
        var relayPositions: Set<[Int]> = []

        sowing: while true {
            while seeds > 0 {
                index = (index + 1) % Self.houseCount
                if index == origin {
                    steps.append(.skipped)
                    continue
                }
                board[index] += 1
                seeds -= 1
                steps.append(.dropped(house: index, count: board[index]))
                if board[index] == Self.seedsPerHouse {
                    // A four: the owner of the house takes it — unless it is the sower's last seed
                    // on the opponent's territory, which the sower takes.
                    let owner = territory[index]
                    let by: Player = owner == mover ? mover : (seeds == 0 ? mover : owner)
                    board[index] = 0
                    stores[by.rawValue] += Self.seedsPerHouse
                    steps.append(.captured(house: index, seeds: Self.seedsPerHouse, by: by))
                    if board.reduce(0, +) + seeds == Self.seedsPerHouse {
                        // The penultimate four has gone; the last four (on the board or still in
                        // hand) go to the same player.
                        for house in 0..<Self.houseCount where board[house] > 0 {
                            steps.append(.captured(house: house, seeds: board[house], by: by))
                            stores[by.rawValue] += board[house]
                            board[house] = 0
                        }
                        stores[by.rawValue] += seeds
                        seeds = 0
                        roundSettled = true
                        break sowing
                    }
                }
            }
            // An empty landing (a house that was empty, or one just captured) ends the turn.
            guard board[index] > 1, laps < Self.maxRelayLaps else { break }
            guard relayPositions.insert(board + [index]).inserted else { break }
            laps += 1
            seeds = board[index]
            board[index] = 0
            origin = index
            steps.append(.relayed(house: index, seeds: seeds))
        }
        _ = roundSettled
        return Sowing(houses: board, stores: stores, steps: steps, lastHouse: index, captured: [], mover: mover)
    }

    /// Abapa: a grand slam captures every seed on the opponent's side.
    static func isGrandSlam(_ sowing: Sowing, in state: GameState) -> Bool {
        guard !sowing.captured.isEmpty else { return false }
        let opponent = sowing.mover.opponent
        let remaining = state.houses(of: opponent)
            .filter { !sowing.captured.contains($0) }
            .reduce(0) { $0 + sowing.houses[$1] }
        return remaining == 0
    }

    private mutating func sweep(_ player: Player, into events: inout [MoveEvent]) {
        let seeds = seedsOnSide(of: player)
        guard seeds > 0 else { return }
        for house in houses(of: player) { houses[house] = 0 }
        stores[player.rawValue] += seeds
        events.append(.sweep(player: player, seeds: seeds))
    }

    private mutating func finish(reason: GameEndReason, events: inout [MoveEvent]) {
        let south = stores[Player.south.rawValue]
        let north = stores[Player.north.rawValue]
        let result: GameOutcome
        if south > north { result = .win(.south, reason) }
        else if north > south { result = .win(.north, reason) }
        else { result = .draw(reason) }
        outcome = result
        events.append(.gameOver(result))
    }
}

// MARK: - Debug rendering

extension GameState: CustomStringConvertible {
    /// ASCII board from south's seat. North's houses read right-to-left (B1 on the right).
    public var description: String {
        let north = (6..<12).reversed().map { String(format: "%2d", houses[$0]) }.joined(separator: " ")
        let south = (0..<6).map { String(format: "%2d", houses[$0]) }.joined(separator: " ")
        let toMove = isOver ? "game over" : "\(sideToMove.label) to move"
        let roundInfo = rules.variant == .namNam ? "  round \(round), territory \(territory.map(\.label).joined())" : ""
        return """
        B store \(stores[1])   [\(north)]  ← B (B6…B1)
        A store \(stores[0])   [\(south)]  → A (A1…A6)   \(toMove)\(roundInfo)
        """
    }
}
