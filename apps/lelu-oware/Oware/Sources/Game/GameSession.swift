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
    /// Outcome of the last attempt in puzzle mode.
    enum PuzzleAttempt: Equatable { case solved, wrong(Move) }
    private(set) var puzzleAttempt: PuzzleAttempt?
    /// Tutorial: index of the current step and whether its required move was completed.
    private(set) var tutorialStepDone = false
    /// True while a hint is being computed.
    private(set) var isHinting = false
    private var hintTask: Task<Void, Never>?

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

    var hasResumableGame: Bool { mode.isResumable && state.moveNumber > 0 && !state.isOver }
    var isGameOver: Bool { state.isOver }
    var sideToMove: Player { state.sideToMove }
    var humanToMove: Bool {
        if case .puzzle = mode, puzzleAttempt == .solved { return false }
        if case .tutorial = mode, tutorialStepDone { return false }
        return !state.isOver && !isAnimating && !isThinking && mode.aiSide != state.sideToMove
    }
    var canUndo: Bool {
        mode.isResumable && !history.isEmpty && !isAnimating && !isThinking
    }
    var currentPuzzle: Puzzle? {
        if case let .puzzle(p) = mode { return p }
        return nil
    }
    var currentTutorialStep: Tutorial.Step? {
        if case let .tutorial(i) = mode, Tutorial.steps.indices.contains(i) { return Tutorial.steps[i] }
        return nil
    }
    /// The house the lesson wants tapped next, if any.
    var highlightedHouse: Int? {
        guard let step = currentTutorialStep, !tutorialStepDone, let move = step.requiredMove else { return nil }
        return move.absoluteIndex
    }
    /// A short name for whoever the human is playing.
    var opponentName: String {
        switch mode {
        case let .versusAI(difficulty, _, _): difficulty.displayName
        case .passAndPlay: sideToMove == .south ? "B" : "A"
        case .journey: mode.journeyOpponent?.name ?? "Journey"
        case .puzzle: "Ananse"
        case .tutorial: "Nana"
        }
    }
    var opponentRole: String? {
        switch mode {
        case .versusAI: "computer"
        case .journey: mode.journeyOpponent?.role
        default: nil
        }
    }
    func isHumanSide(_ player: Player) -> Bool { mode.aiSide != player }

    var turnDescription: String {
        if let puzzle = currentPuzzle {
            switch puzzleAttempt {
            case .solved: return "Ayekoo — well done"
            case .wrong: return "Not that one. Try again."
            case nil: return puzzle.kind.instruction
            }
        }
        if let step = currentTutorialStep { return step.prompt }
        if let outcome = state.outcome { return Self.describe(outcome, mode: mode) }
        if isThinking { return "Thinking…" }
        switch mode {
        case .versusAI, .journey: return humanToMove ? "Your move" : "…"
        case .passAndPlay: return state.sideToMove == .south ? "A to move" : "B to move"
        case .puzzle, .tutorial: return ""
        }
    }

    static func describe(_ outcome: GameOutcome, mode: GameMode) -> String {
        switch outcome {
        case let .win(player, reason):
            let who: String
            switch mode {
            case .versusAI(_, _, let human): who = player == human ? "You win" : "You lose"
            case .passAndPlay: who = "\(player.label) wins"
            case .puzzle, .tutorial, .journey: who = player == .south ? "You win" : "You lose"
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
        puzzleAttempt = nil
        tutorialStepDone = false
        isThinking = false
        isAnimating = false
        persist()
        animator?.render(state)
        scheduleAIIfNeeded()
    }

    /// Start (or restart) a puzzle. Ordinary saved games are left untouched.
    func startPuzzle(_ puzzle: Puzzle) {
        aiTask?.cancel()
        mode = .puzzle(puzzle)
        state = puzzle.state
        history = []
        previewMove = nil
        puzzleAttempt = nil
        isThinking = false
        isAnimating = false
        animator?.render(state)
    }

    func retryPuzzle() {
        guard let puzzle = currentPuzzle else { return }
        startPuzzle(puzzle)
    }

    /// Jump to a tutorial step.
    func startTutorial(step index: Int) {
        aiTask?.cancel()
        let step = Tutorial.steps[min(max(index, 0), Tutorial.steps.count - 1)]
        mode = .tutorial(step: index)
        state = step.position ?? .initial
        history = []
        previewMove = nil
        tutorialStepDone = step.requiredMove == nil
        isThinking = false
        isAnimating = false
        animator?.render(state)
    }

    func advanceTutorial() {
        guard case let .tutorial(i) = mode else { return }
        if i + 1 < Tutorial.steps.count { startTutorial(step: i + 1) }
    }

    /// Human taps a house (0–5 relative to the side to move).
    func play(house: Int) {
        guard humanToMove else { return }
        let move = Move(player: state.sideToMove, house: house)
        guard state.isLegal(move) else { return }
        if let puzzle = currentPuzzle {
            if puzzle.isSolved(by: move) {
                puzzleAttempt = .solved
                Task { await perform(move) }
            } else {
                puzzleAttempt = .wrong(move)
            }
            return
        }
        if let step = currentTutorialStep, let required = step.requiredMove {
            guard move == required else { return }
            Task {
                await perform(move)
                tutorialStepDone = true
            }
            return
        }
        Task { await perform(move) }
    }

    /// Why a house cannot be played right now, for a quiet hint. Nil if it can.
    func reasonHouseIsBlocked(_ house: Int) -> String? {
        guard !state.isOver else { return nil }
        let move = Move(player: state.sideToMove, house: house)
        if state.houses[move.absoluteIndex] == 0 { return "Empty house" }
        if let step = currentTutorialStep, let required = step.requiredMove, move != required {
            return "Try \(required.notation) for this step"
        }
        if state.isLegal(move) { return nil }
        if state.sideIsEmpty(state.sideToMove.opponent) { return "You must give the other side seeds" }
        return "Not allowed"
    }

    /// Hints are offered in ordinary games and the Journey, never in riddles or the lesson.
    var canHint: Bool { mode.isResumable && humanToMove && !isHinting }

    /// Nyansapo: show the strong engine's suggestion as a landing preview for a moment.
    func requestHint() {
        guard canHint else { return }
        isHinting = true
        let snapshot = state
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            let suggestion = await Task.detached(priority: .userInitiated) {
                AIPlayer.analyse(snapshot, depth: 8, timeBudget: .milliseconds(900))?.move
            }.value
            guard let self, !Task.isCancelled, self.state == snapshot else { self?.isHinting = false; return }
            self.isHinting = false
            guard let suggestion else { return }
            self.previewMove = suggestion
            try? await Task.sleep(for: .seconds(2.2))
            if self.previewMove == suggestion { self.previewMove = nil }
        }
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

    /// Change the computer's level mid-game (vs AI only). The position is kept; if the AI is
    /// currently thinking it restarts at the new level.
    var canChangeDifficulty: Bool {
        if case .versusAI = mode { return true }
        return false
    }

    func changeDifficulty(to difficulty: Difficulty) {
        guard case let .versusAI(_, personality, human) = mode else { return }
        aiTask?.cancel()
        isThinking = false
        mode = .versusAI(difficulty: difficulty, personality: personality, humanPlays: human)
        persist()
        scheduleAIIfNeeded()
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
        guard mode.isResumable else { return }
        store.save(SavedGame(state: state, mode: mode, history: history))
    }
}
