/// Pure, UI-independent Oware (Abapa) rules engine.
///
/// Houses 0–5 belong to `.south` (A1–A6), 6–11 to `.north` (B1–B6), indexed counter-clockwise.
/// The board always holds 48 seeds across houses and stores.
public struct GameState: Sendable, Hashable, Codable {
    public static let houseCount = 12
    public static let seedsPerHouse = 4
    public static let totalSeeds = houseCount * seedsPerHouse

    public var houses: [Int]
    public var stores: [Int]
    public var sideToMove: Player
    public var rules: RuleSet
    /// Number of moves played so far.
    public var moveNumber: Int
    /// Set once the game has ended.
    public var outcome: GameOutcome?
    /// How many times each position (houses + side to move) has occurred; drives cycle detection.
    public var positionCounts: [String: Int]
    public var lastMove: Move?

    public init(
        houses: [Int],
        stores: [Int] = [0, 0],
        sideToMove: Player = .south,
        rules: RuleSet = .abapa
    ) {
        precondition(houses.count == Self.houseCount, "Oware has 12 houses")
        precondition(stores.count == 2, "Two players, two stores")
        precondition(houses.allSatisfy { $0 >= 0 } && stores.allSatisfy { $0 >= 0 }, "no negative seeds")
        self.houses = houses
        self.stores = stores
        self.sideToMove = sideToMove
        self.rules = rules
        self.moveNumber = 0
        self.outcome = nil
        self.positionCounts = [:]
        self.lastMove = nil
        self.positionCounts[positionKey] = 1
    }

    /// The standard opening position: four seeds in every house, south to move.
    public static let initial = GameState(houses: Array(repeating: seedsPerHouse, count: houseCount))

    public static func initial(rules: RuleSet) -> GameState {
        GameState(houses: Array(repeating: seedsPerHouse, count: houseCount), rules: rules)
    }

    // MARK: - Queries

    public var isOver: Bool { outcome != nil }
    public var seedsOnBoard: Int { houses.reduce(0, +) }
    public var totalSeeds: Int { seedsOnBoard + stores.reduce(0, +) }

    public func seeds(in house: Int) -> Int { houses[house] }
    public func store(of player: Player) -> Int { stores[player.rawValue] }
    public func seedsOnSide(of player: Player) -> Int { player.houseRange.reduce(0) { $0 + houses[$1] } }
    public func sideIsEmpty(_ player: Player) -> Bool { seedsOnSide(of: player) == 0 }

    /// Compact key for repetition detection and transposition tables.
    public var positionKey: String {
        houses.map(String.init).joined(separator: ",") + "|" + sideToMove.label
    }

    // MARK: - Legal moves

    /// Moves the side to move may play right now, honouring the feeding obligation
    /// and (if configured) the illegal-grand-slam rule. Empty when the game is over.
    public func legalMoves() -> [Move] {
        guard !isOver else { return [] }
        let player = sideToMove
        let candidates = (0..<6)
            .map { Move(player: player, house: $0) }
            .filter { houses[$0.absoluteIndex] > 0 }

        var moves = candidates
        if rules.mustFeed && sideIsEmpty(player.opponent) {
            let feeding = candidates.filter { sowingReachesOpponent($0) }
            if !feeding.isEmpty { moves = feeding }
            // If no move can feed, every move is "legal" but apply() will end the game instead.
        }
        if rules.grandSlam == .illegalMove {
            moves = moves.filter { !Self.isGrandSlam(simulateSowing($0)) }
        }
        return moves
    }

    public func isLegal(_ move: Move) -> Bool { legalMoves().contains(move) }

    /// True if sowing from this house drops at least one seed on the opponent's side.
    func sowingReachesOpponent(_ move: Move) -> Bool {
        let seeds = houses[move.absoluteIndex]
        let distanceToOpponent = move.player.houseRange.upperBound - move.absoluteIndex
        return seeds >= distanceToOpponent
    }

    // MARK: - Applying moves

    /// Play a move, returning the events in order. Throws if the move is illegal.
    @discardableResult
    public mutating func apply(_ move: Move) throws -> [MoveEvent] {
        guard !isOver else { throw MoveError.gameIsOver }
        guard move.player == sideToMove else { throw MoveError.notYourTurn }
        guard houses[move.absoluteIndex] > 0 else { throw MoveError.emptyHouse }

        let mover = move.player
        let opponent = mover.opponent
        let opponentWasEmpty = sideIsEmpty(opponent)

        // Feeding obligation.
        if rules.mustFeed && opponentWasEmpty && !sowingReachesOpponent(move) {
            let anyFeeding = (0..<6).map { Move(player: mover, house: $0) }
                .contains { houses[$0.absoluteIndex] > 0 && sowingReachesOpponent($0) }
            if anyFeeding { throw MoveError.mustFeedOpponent }
            // Nobody can be fed: the mover keeps their own seeds and the game ends.
            var events: [MoveEvent] = []
            sweep(mover, into: &events)
            finish(reason: .opponentCouldNotBeFed, events: &events)
            return events
        }

        var events: [MoveEvent] = []

        // Sow.
        let origin = move.absoluteIndex
        let sowing = simulateSowing(move)
        events.append(.pickUp(house: origin, seeds: houses[origin]))
        houses = sowing.houses
        for step in sowing.steps {
            switch step {
            case let .dropped(house, count): events.append(.sow(house: house, count: count))
            case .skipped: events.append(.skipOrigin(house: origin))
            }
        }

        // Capture.
        let captured = sowing.captured
        if !captured.isEmpty {
            let grandSlam = Self.isGrandSlam(sowing)
            if grandSlam && rules.grandSlam == .illegalMove {
                throw MoveError.grandSlamNotAllowed
            }
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
        finish(reason: .agreement, events: &events)
        return events
    }

    // MARK: - Internals

    enum SowStep: Hashable { case dropped(house: Int, count: Int), skipped }

    struct Sowing: Hashable {
        var houses: [Int]
        var steps: [SowStep]
        var lastHouse: Int
        /// Opponent houses captured, in capture order (last-sown house first, walking backwards).
        var captured: [Int]
        var mover: Player
    }

    /// Compute the result of sowing without mutating state.
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
        while opponent.owns(walk) && (board[walk] == 2 || board[walk] == 3) {
            captured.append(walk)
            walk -= 1
        }
        return Sowing(houses: board, steps: steps, lastHouse: index, captured: captured, mover: move.player)
    }

    /// A grand slam captures every seed on the opponent's side.
    static func isGrandSlam(_ sowing: Sowing) -> Bool {
        guard !sowing.captured.isEmpty else { return false }
        let opponent = sowing.mover.opponent
        let remaining = opponent.houseRange
            .filter { !sowing.captured.contains($0) }
            .reduce(0) { $0 + sowing.houses[$1] }
        return remaining == 0
    }

    private mutating func sweep(_ player: Player, into events: inout [MoveEvent]) {
        let seeds = seedsOnSide(of: player)
        guard seeds > 0 else { return }
        for house in player.houseRange { houses[house] = 0 }
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
        return """
        B store \(stores[1])   [\(north)]  ← B (B6…B1)
        A store \(stores[0])   [\(south)]  → A (A1…A6)   \(toMove)
        """
    }
}
