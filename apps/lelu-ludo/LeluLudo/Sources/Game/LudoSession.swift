import Foundation
import LudoAI
import LudoEngine
import Observation

/// The game as the app plays it: who sits where, the dice, the computer's turns and the save.
/// The screens read it and call `roll()`, `tap(token:)` and `play(_:)`; computer seats play by themselves.
@MainActor
@Observable
final class LudoSession {
    private(set) var setup: GameSetup
    private(set) var state: GameState
    /// The last roll and who made it, for the dice on screen.
    private(set) var lastRoll: (color: PlayerColor, value: Int)?
    /// What the last action did, for animation and VoiceOver.
    private(set) var lastEvents: [GameEvent] = []
    private(set) var isComputerPlaying = false
    /// Whether there is a game to continue.
    private(set) var hasGame = false
    /// How long things take on screen, so people can follow them; `.instant` in tests.
    struct Pacing: Equatable {
        /// Before each computer action.
        var computer: Duration
        /// Per square as a token walks its path.
        var step: Duration
        /// While the die tumbles across the board, before a computer plays the roll.
        var roll: Duration
        static let normal = Pacing(computer: .milliseconds(600), step: .milliseconds(130), roll: .milliseconds(750))
        static let instant = Pacing(computer: .zero, step: .zero, roll: .zero)
    }
    @ObservationIgnored var pacing = Pacing.normal
    /// Counts rolls, so the board can tumble a die for each one.
    private(set) var rolls = 0

    /// A token on its way: the squares of its path and how far along it is. Kicks happen when it arrives.
    struct Motion: Equatable {
        let color: PlayerColor
        let token: Int
        let cells: [Board.Cell]
        var step: Int
        var cell: Board.Cell { cells[step] }
    }
    private(set) var motion: Motion?
    /// The token whose moves are being offered (it has more than one).
    private(set) var selectedToken: Int?
    /// What has just happened, newest last, in words (also read out by VoiceOver).
    private(set) var log: [String] = []

    @ObservationIgnored private let store: GameStore
    @ObservationIgnored private let dice: DiceSource
    @ObservationIgnored private let feedback: FeedbackPlayer?
    @ObservationIgnored private var aiSeed: UInt64
    @ObservationIgnored private var aiRolls: UInt64 = 0

    init(store: GameStore = .shared, dice: DiceSource = RandomDice(), feedback: FeedbackPlayer? = nil) {
        self.store = store
        self.dice = dice
        self.feedback = feedback
        if let saved = store.load() {
            setup = saved.setup
            state = saved.state
            aiSeed = saved.aiSeed
            hasGame = !saved.state.isOver
        } else {
            setup = GameSetup(seats: [.red: .human, .black: .computer(.novice)])
            state = GameState(players: [.red, .black])
            aiSeed = UInt64.random(in: 0...UInt64.max)
        }
    }

    /// Starts from an arranged position (UI tests, screenshots).
    func load(_ scenario: Scenario) {
        let (setup, state) = scenario.game
        self.setup = setup
        self.state = state
        lastRoll = nil
        log = []
        hasGame = true
        save()
    }

    func newGame(_ setup: GameSetup) {
        self.setup = setup
        state = GameState(players: setup.colors, rules: setup.rules)
        aiSeed = UInt64.random(in: 0...UInt64.max)
        lastRoll = nil
        lastEvents = []
        hasGame = true
        save()
    }

    private var humanToMove: Bool { setup.seat(state.toMove) == .human }

    /// The person whose turn it is may roll.
    var canRoll: Bool { !state.isOver && humanToMove && state.pendingRoll == nil && !isComputerPlaying }

    /// Tokens the person to move may play with the current roll.
    var movableTokens: [Int] {
        guard humanToMove, !isComputerPlaying else { return [] }
        return Array(Set(state.legalMoves().map(\.token))).sorted()
    }

    /// Every move a token can make with the roll (forward, back kick, side kick, home kick…).
    func choices(for token: Int) -> [Move] {
        guard humanToMove, !isComputerPlaying, motion == nil else { return [] }
        return state.legalMoves().filter { $0.token == token }
    }

    /// Whether a token has a move other than plain forward (shown on the board).
    func hasKickChoice(_ token: Int) -> Bool { choices(for: token).contains { $0.kind != .forward && $0.kind != .enter } }

    /// The squares a move would pass through, for markers and previews.
    func path(for move: Move) -> [Board.Cell] { state.path(for: move) }

    /// Tap a token: one move plays at once; with several, the token is selected and they are offered.
    func tap(token: Int) async {
        let moves = choices(for: token)
        if moves.count == 1 {
            await play(moves[0])
        } else if moves.count > 1 {
            selectedToken = selectedToken == token ? nil : token
        }
    }

    func cancelChoice() { selectedToken = nil }

    /// A player's or computer's name, as the game says it.
    func name(_ color: PlayerColor) -> String {
        switch setup.seat(color) {
        case .human: setup.seats.values.filter({ $0 == .human }).count > 1 ? color.name : "You"
        case .computer: color.name
        }
    }

    /// The computers' level, when there are computers (they all play at one level).
    var computerLevel: LudoAIDifficulty? {
        for color in setup.colors { if case let .computer(level) = setup.seat(color) { return level } }
        return nil
    }

    /// Changes every computer opponent's level, mid-game; the game carries on from where it is.
    func changeLevel(to level: LudoAIDifficulty) {
        guard computerLevel != nil else { return }
        var seats = setup.seats
        for (color, seat) in seats { if case .computer = seat { seats[color] = .computer(level) } }
        setup = GameSetup(seats: seats, rules: setup.rules)
        save()
    }

    func roll() async {
        guard canRoll else { return }
        rollDie()
        await runComputerTurns()
    }

    /// Plays one of `choices(for:)`.
    func play(_ move: Move) async {
        guard humanToMove, !isComputerPlaying, motion == nil, state.legalMoves().contains(move) else { return }
        selectedToken = nil
        await perform(move)
        await runComputerTurns()
    }

    /// Walks the token along its path, then plays the move (kicks land as it arrives).
    private func perform(_ move: Move) async {
        let mover = state.toMove
        let cells = state.path(for: move)
        if pacing.step > .zero, !cells.isEmpty {
            motion = Motion(color: mover, token: move.token, cells: cells, step: 0)
            for i in cells.indices {
                motion?.step = i
                feedback?.play(.step)
                try? await Task.sleep(for: pacing.step)
            }
        } else {
            for _ in cells { feedback?.play(.step) }
        }
        guard let events = try? state.apply(move) else { motion = nil; return }
        motion = nil
        lastEvents = events
        describe(events)
        sound(events)
        save()
    }

    /// The feedback for what a move or roll did (the steps are played as the token walks).
    private func sound(_ events: [GameEvent]) {
        for event in events {
            switch event {
            case .kicked, .kickedInLane: feedback?.play(.kick)
            case .reachedHome: feedback?.play(.home)
            case .threeSixes: feedback?.play(.threeSixes)
            case .won: feedback?.play(.win)
            default: break
            }
        }
    }

    /// Lets computer seats play until it is a person's turn or the game is over.
    func runComputerTurns() async {
        guard !isComputerPlaying else { return }
        isComputerPlaying = true
        defer { isComputerPlaying = false }
        while !state.isOver, case let .computer(level) = setup.seat(state.toMove) {
            if pacing.computer > .zero { try? await Task.sleep(for: pacing.computer) }
            if state.pendingRoll == nil {
                rollDie()
                if pacing.roll > .zero { try? await Task.sleep(for: pacing.roll) }
            }
            guard !state.isOver, state.pendingRoll != nil, case .computer = setup.seat(state.toMove) else { continue }
            var rng = SeededGenerator(seed: aiSeed &+ aiRolls)
            aiRolls &+= 1
            if let move = AIPlayer(difficulty: level).chooseMove(state, using: &rng) {
                await perform(move)
            }
        }
    }

    private func rollDie() {
        let color = state.toMove
        let value = dice.roll()
        lastRoll = (color, value)
        rolls += 1
        feedback?.play(.roll)
        lastEvents = state.roll(value)
        describe(lastEvents)
        sound(lastEvents)
        save()
    }

    /// Puts what just happened into words for the log (and VoiceOver).
    private func describe(_ events: [GameEvent]) {
        var kind: Move.Kind = .forward
        func whose(_ c: PlayerColor) -> String { name(c) == "You" ? "your" : "\(c.name)'s" }
        for event in events {
            var line: String?
            switch event {
            case let .moved(_, move): kind = move.kind
            case let .kicked(color, _, _, by), let .kickedInLane(color, _, _, _, by):
                let verb: String = switch kind {
                case .backKick: "back-kicked"
                case .sideKickForward, .sideKickBack: "side-kicked"
                case .homeKick: "home-kicked"
                default: "kicked"
                }
                line = "\(name(by)) \(verb) \(whose(color)) token home"
            case let .reachedHome(color, _): line = "\(name(color)) brought a token home"
            case let .threeSixes(color): line = "Three sixes: \(whose(color)) turn is undone"
            case let .passed(color): line = "\(name(color)) \(name(color) == "You" ? "have" : "has") no move"
            default: break
            }
            if let line {
                log.append(line.prefix(1).uppercased() + line.dropFirst())
                if log.count > 4 { log.removeFirst(log.count - 4) }
            }
        }
    }

    private func save() {
        if state.isOver {
            store.clear()
            hasGame = false
        } else {
            store.save(SavedGame(setup: setup, state: state, aiSeed: aiSeed))
        }
    }
}
