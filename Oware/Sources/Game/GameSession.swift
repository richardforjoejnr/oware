import Foundation
import Observation
import OwareEngine
import OwareAI

/// Something that can animate a move's events on screen (the SpriteKit board).
@MainActor
protocol BoardAnimator: AnyObject {
    func animate(events: [MoveEvent], from before: GameState, to after: GameState) async
    func render(_ state: GameState)
}

/// Drives one game: applies moves to the engine, asks the animator to play them, runs the AI
/// off the main thread, supports undo, and persists after every move.
@MainActor
@Observable
final class GameSession {
    private(set) var state: GameState
    private(set) var mode: GameMode
    private(set) var history: [GameState] = []
    private(set) var isAnimating = false
    private(set) var isThinking = false
    /// The house the player is previewing with a long press, if any.
    var previewMove: Move?

    weak var animator: (any BoardAnimator)?
    private var aiTask: Task<Void, Never>?
    private let store: GameStore
    /// Minimum "thinking" pause so the AI never replies instantly.
    var minimumThinkTime: Duration = .milliseconds(650)

    init(store: GameStore = .shared) {
        self.store = store
        if let saved = store.load(), !saved.state.isOver {
            state = saved.state
            mode = saved.mode
            history = saved.history
        } else {
            state = .initial
            mode = .passAndPlay
        }
    }

    // MARK: - Derived

    var hasResumableGame: Bool { state.moveNumber > 0 && !state.isOver }
    var isGameOver: Bool { state.isOver }
    var sideToMove: Player { state.sideToMove }
    var humanToMove: Bool {
        !state.isOver && !isAnimating && !isThinking && mode.aiSide != state.sideToMove
    }
    var canUndo: Bool {
        !history.isEmpty && !isAnimating && !isThinking
    }
    func isHumanSide(_ player: Player) -> Bool { mode.aiSide != player }

    var turnDescription: String {
        if let outcome = state.outcome { return Self.describe(outcome, mode: mode) }
        if isThinking { return "Thinking…" }
        switch mode {
        case .versusAI: return humanToMove ? "Your move" : "…"
        case .passAndPlay: return state.sideToMove == .south ? "A to move" : "B to move"
        }
    }

    static func describe(_ outcome: GameOutcome, mode: GameMode) -> String {
        switch outcome {
        case let .win(player, reason):
            let who: String
            switch mode {
            case .versusAI(_, _, let human): who = player == human ? "You win" : "You lose"
            case .passAndPlay: who = "\(player.label) wins"
            }
            return who + reasonSuffix(reason)
        case let .draw(reason):
            return "Draw" + reasonSuffix(reason)
        }
    }

    private static func reasonSuffix(_ reason: GameEndReason) -> String {
        switch reason {
        case .reachedWinningSeeds, .boardEmpty: ""
        case .opponentCouldNotBeFed: " — no seeds could be given"
        case .repetition: " — the game went round in circles"
        case .noLegalMoves: " — no moves left"
        case .grandSlam: " — grand slam"
        case .agreement: " — by agreement"
        }
    }

    // MARK: - Commands

    func newGame(_ mode: GameMode, rules: RuleSet = .abapa) {
        aiTask?.cancel()
        self.mode = mode
        state = .initial(rules: rules)
        history = []
        previewMove = nil
        isThinking = false
        isAnimating = false
        persist()
        animator?.render(state)
        scheduleAIIfNeeded()
    }

    /// Human taps a house (0–5 relative to the side to move).
    func play(house: Int) {
        guard humanToMove else { return }
        let move = Move(player: state.sideToMove, house: house)
        guard state.isLegal(move) else { return }
        Task { await perform(move) }
    }

    /// Why a house cannot be played right now, for a quiet hint. Nil if it can.
    func reasonHouseIsBlocked(_ house: Int) -> String? {
        guard !state.isOver else { return nil }
        let move = Move(player: state.sideToMove, house: house)
        if state.houses[move.absoluteIndex] == 0 { return "Empty house" }
        if state.isLegal(move) { return nil }
        if state.sideIsEmpty(state.sideToMove.opponent) { return "You must give the other side seeds" }
        return "Not allowed"
    }

    func undo() {
        guard canUndo else { return }
        aiTask?.cancel()
        isThinking = false
        // Against the AI, undo both the AI's reply and your own move.
        var target = history.removeLast()
        if mode.aiSide != nil, let aiSide = mode.aiSide, target.sideToMove == aiSide, !history.isEmpty {
            target = history.removeLast()
        }
        state = target
        previewMove = nil
        persist()
        animator?.render(state)
    }

    func resign() {
        guard !state.isOver else { return }
        aiTask?.cancel()
        _ = state.endByAgreement()
        persist()
        animator?.render(state)
    }

    /// Re-render after the board view (re)appears.
    func attach(_ animator: any BoardAnimator) {
        self.animator = animator
        animator.render(state)
        scheduleAIIfNeeded()
    }

    // MARK: - Internals

    private func perform(_ move: Move) async {
        let before = state
        guard let result = try? state.applying(move) else { return }
        history.append(before)
        state = result.state
        previewMove = nil
        persist()
        isAnimating = true
        if let animator {
            await animator.animate(events: result.events, from: before, to: result.state)
        }
        isAnimating = false
        scheduleAIIfNeeded()
    }

    private func scheduleAIIfNeeded() {
        guard let ai = mode.aiPlayer, let aiSide = mode.aiSide,
              !state.isOver, state.sideToMove == aiSide, !isThinking, !isAnimating else { return }
        isThinking = true
        let snapshot = state
        let minimum = minimumThinkTime
        aiTask = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            let chosen = await Task.detached(priority: .userInitiated) {
                ai.chooseMove(for: snapshot, seed: UInt64(snapshot.moveNumber) &* 7919)
            }.value
            let elapsed = clock.now - start
            if elapsed < minimum { try? await Task.sleep(for: minimum - elapsed) }
            guard let self, !Task.isCancelled, self.state == snapshot, let chosen else {
                self?.isThinking = false
                return
            }
            self.isThinking = false
            await self.perform(chosen)
        }
    }

    private func persist() {
        store.save(SavedGame(state: state, mode: mode, history: history))
    }
}
