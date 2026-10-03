import Foundation
import LudoAI
import LudoEngine
import Observation

/// The game as the app plays it: who sits where, the dice, the computer's turns and the save.
/// The screens read it and call `roll()` and `play(token:)`; computer seats play by themselves.
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
    /// Pause between computer actions so people can follow them (zero in tests).
    @ObservationIgnored var computerPause: Duration = .milliseconds(700)

    @ObservationIgnored private let store: GameStore
    @ObservationIgnored private let dice: DiceSource
    @ObservationIgnored private var aiSeed: UInt64
    @ObservationIgnored private var aiRolls: UInt64 = 0

    init(store: GameStore = .shared, dice: DiceSource = RandomDice()) {
        self.store = store
        self.dice = dice
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

    /// The move a token would make (the forward one when a back kick is also possible).
    func move(for token: Int) -> Move? {
        let moves = state.legalMoves().filter { $0.token == token }
        return moves.first { $0.kind != .backKick } ?? moves.first
    }

    func roll() async {
        guard canRoll else { return }
        rollDie()
        await runComputerTurns()
    }

    func play(token: Int) async {
        guard humanToMove, let move = move(for: token) else { return }
        await play(move)
    }

    /// Plays a chosen move (a back kick is chosen this way when both are possible).
    func play(_ move: Move) async {
        guard humanToMove, !isComputerPlaying, let events = try? state.apply(move) else { return }
        lastEvents = events
        save()
        await runComputerTurns()
    }

    /// Lets computer seats play until it is a person's turn or the game is over.
    func runComputerTurns() async {
        guard !isComputerPlaying else { return }
        isComputerPlaying = true
        defer { isComputerPlaying = false }
        while !state.isOver, case let .computer(level) = setup.seat(state.toMove) {
            if computerPause > .zero { try? await Task.sleep(for: computerPause) }
            if state.pendingRoll == nil { rollDie() }
            guard !state.isOver, state.pendingRoll != nil, case .computer = setup.seat(state.toMove) else { continue }
            var rng = SeededGenerator(seed: aiSeed &+ aiRolls)
            aiRolls &+= 1
            if let move = AIPlayer(difficulty: level).chooseMove(state, using: &rng), let events = try? state.apply(move) {
                if computerPause > .zero { try? await Task.sleep(for: computerPause) }
                lastEvents = events
                save()
            }
        }
    }

    private func rollDie() {
        let color = state.toMove
        let value = dice.roll()
        lastRoll = (color, value)
        lastEvents = state.roll(value)
        save()
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
