import Foundation
import Observation
import UIKit
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
    /// Rules for the lesson now showing (follows Settings when the lesson starts).
    private(set) var lessonVariant: RuleSet.Variant = .abapa
    var tutorialSteps: [Tutorial.Step] { Tutorial.steps(for: lessonVariant) }

    var currentTutorialStep: Tutorial.Step? {
        if case let .tutorial(i) = mode, tutorialSteps.indices.contains(i) { return tutorialSteps[i] }
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
        case .territory: " — every house is theirs"
        case .roundLimit: " — on houses held after the last round"
        }
    }

    // MARK: - Commands

    /// `rules` nil keeps the rules of the game on the board (so Play again and Next opponent
    /// stay in the same variant).
    func newGame(_ mode: GameMode, rules: RuleSet? = nil) {
        aiTask?.cancel()
        let rules = rules ?? state.rules
        self.mode = mode
        state = .initial(rules: rules)
        history = []
        previewMove = nil
        roundMessage = nil
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
    func startTutorial(step index: Int, variant: RuleSet.Variant? = nil) {
        if let variant { lessonVariant = variant }
        aiTask?.cancel()
        let step = tutorialSteps[min(max(index, 0), tutorialSteps.count - 1)]
        mode = .tutorial(step: index)
        state = step.position ?? .initial(rules: lessonVariant == .namNam ? .namNam : .abapa)
        history = []
        previewMove = nil
        tutorialStepDone = step.requiredMove == nil
        isThinking = false
        isAnimating = false
        animator?.render(state)
    }

    func advanceTutorial() {
        guard case let .tutorial(i) = mode else { return }
        if i + 1 < tutorialSteps.count { startTutorial(step: i + 1) }
        if i + 1 == tutorialSteps.count - 1 { PlayerEvents.shared.lessonCompleted(rules: lessonVariant) }
    }

    /// Human taps a house (0–5 relative to the side to move).
    /// Nam-Nam: set for a few seconds after a round ends, for the board to show as a hint.
    var roundMessage: String?

    /// `house` is the absolute board index 0–11.
    func play(house: Int) {
        guard humanToMove else { return }
        let move = Move(player: state.sideToMove, absoluteHouse: house)
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
        let move = Move(player: state.sideToMove, absoluteHouse: house)
        if state.owner(of: house) != state.sideToMove { return state.rules.variant == .namNam ? "That house is theirs this round" : "Not your house" }
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

    /// A game in progress that a player may end (resign or agree to stop).
    var canEndGame: Bool { mode.isResumable && !state.isOver }

    /// `player` resigns (default: you against the computer, or whoever is to move in Pass & Play).
    /// Resigning ends the whole game (in Nam-Nam, not just the round): the other side wins.
    func resign(_ player: Player? = nil) {
        guard canEndGame else { return }
        aiTask?.cancel()
        isThinking = false
        let loser = player ?? mode.aiSide?.opponent ?? state.sideToMove
        state.outcome = .win(loser.opponent, .agreement)
        persist()
        animator?.render(state)
    }

    /// Both sides stop here and each keeps the seeds on their own side. Abapa: the game ends and the
    /// scores decide it. Nam-Nam: the round ends and houses are shared out as usual.
    func agreeToStop() {
        guard canEndGame else { return }
        aiTask?.cancel()
        isThinking = false
        history.append(state)
        let events = state.endByAgreement()
        if let round = events.compactMap({ if case let .roundOver(r) = $0 { return r } else { return nil } }).last {
            roundMessage = Self.describe(round, previous: state.roundHistory.dropLast().last, in: mode)
        }
        previewMove = nil
        persist()
        animator?.render(state)
        scheduleAIIfNeeded()
    }

    /// Re-render after the board view (re)appears.
    #if DEBUG
    /// Screenshot aid: a mid-game position with `n` seeds in each store, no AI move pending.
    func loadDemoPosition(storeSeeds n: Int) {
        aiTask?.cancel()
        var s = GameState.initial
        let perStore = min(n, 24)
        s.stores = [perStore, perStore]
        let remaining = 48 - perStore * 2
        var houses = Array(repeating: 0, count: 12)
        for i in 0..<remaining { houses[(i * 5) % 12] += 1 }
        s.houses = houses
        state = s
        history = []
        isThinking = false
        isAnimating = false
        animator?.render(state)
    }
    #endif

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
        if let round = result.events.compactMap({ if case let .roundOver(r) = $0 { return r } else { return nil } }).last {
            let previous = result.state.roundHistory.dropLast().last
            roundMessage = Self.describe(round, previous: previous, in: mode)
        }
        persist()
        isAnimating = true
        if let animator {
            await animator.animate(events: result.events, from: before, to: result.state)
        }
        isAnimating = false
        Self.announce(Self.announcement(for: move, events: result.events, after: result.state, mode: mode, opponentName: opponentName))
        scheduleAIIfNeeded()
    }

    // MARK: - VoiceOver

    /// What VoiceOver says once a move has finished on the board: who played where, what was
    /// taken, how a round or the game ended, and whose turn it is.
    static func announcement(for move: Move, events: [MoveEvent], after: GameState, mode: GameMode, opponentName: String) -> String {
        func name(_ p: Player) -> String {
            if case .passAndPlay = mode { return p.label }
            if case .puzzle = mode { return "You" }
            if case .tutorial = mode { return "You" }
            return p == mode.aiSide ? opponentName : "You"
        }
        var taken = [0, 0]
        for case let .capture(_, seeds, by) in events { taken[by.rawValue] += seeds }
        let mover = move.player
        var parts = ["\(name(mover)) played \(move.notation)"]
        if taken[mover.rawValue] > 0 { parts[0] += " and took \(taken[mover.rawValue]) seeds" }
        if taken[mover.opponent.rawValue] > 0 { parts.append("\(name(mover.opponent)) got \(taken[mover.opponent.rawValue])") }
        if let round = events.compactMap({ if case let .roundOver(r) = $0 { return r } else { return nil } }).last {
            parts.append(describe(round, previous: after.roundHistory.dropLast().last, in: mode))
        }
        if let outcome = after.outcome {
            parts.append(describe(outcome, mode: mode))
        } else if case .versusAI = mode, after.sideToMove != mode.aiSide {
            parts.append("Your move")
        } else if case .journey = mode, after.sideToMove != mode.aiSide {
            parts.append("Your move")
        } else if case .passAndPlay = mode {
            parts.append("\(after.sideToMove.label) to move")
        }
        return parts.joined(separator: ". ") + "."
    }

    /// Spoken for the "Preview this move" action.
    static func previewDescription(_ preview: MovePreview) -> String {
        let landing = Move(player: preview.move.player, absoluteHouse: preview.landingHouse).notation
        let taking = preview.capturedSeeds > 0 ? "takes \(preview.capturedSeeds) seeds" : "takes nothing"
        let forfeit = preview.grandSlamForfeited ? ", but the grand slam is forfeited" : ""
        return "\(preview.move.notation): last seed lands in \(landing), \(taking)\(forfeit)."
    }

    /// Speaks now (for an action the player just asked for).
    static func speak(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// Queued so one announcement does not cut off the previous one.
    private static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let queued = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: queued)
    }

    /// "Round 1: you 28, Nana 20 — you gain a house"
    /// The round's seeds and what they did to the houses, measured against the round before:
    /// houses are refilled from each round's seeds, so winning a round can still cost a house.
    static func describe(_ round: RoundResult, previous: RoundResult?, in mode: GameMode) -> String {
        func houses(_ r: RoundResult?, _ p: Player) -> Int {
            guard let r else { return 6 }
            return p == .south ? r.southHouses : r.northHouses
        }
        func change(_ n: Int) -> String { "\(abs(n)) house\(abs(n) == 1 ? "" : "s")" }
        if case .passAndPlay = mode {
            let before = houses(previous, .south), after = houses(round, .south)
            let moved = after - before
            let what = moved == 0 ? "houses stay as they were" : (moved > 0 ? "A takes \(change(moved))" : "B takes \(change(moved))")
            return "Round \(round.round): A \(round.southSeeds), B \(round.northSeeds) — \(what). A \(after), B \(12 - after)"
        }
        let you = mode.aiSide?.opponent ?? .south
        let mine = you == .south ? round.southSeeds : round.northSeeds
        let theirs = you == .south ? round.northSeeds : round.southSeeds
        let before = houses(previous, you), after = houses(round, you)
        let moved = after - before
        let what = moved == 0 ? "you keep \(after) houses" : (moved > 0 ? "you gain \(change(moved)), now \(after)" : "you lose \(change(moved)), now \(after)")
        return "Round \(round.round): you \(mine), them \(theirs) — \(what)"
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
