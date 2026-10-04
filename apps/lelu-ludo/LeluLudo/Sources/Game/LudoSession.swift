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
        /// While a computer's die is thrown (always the quick throw), before it plays the roll.
        var roll: Duration
        /// While your die is thrown, before a move that plays itself (Novice, one move forward).
        var yourRoll: Duration
        static let normal = Pacing(computer: .milliseconds(600), step: .milliseconds(130),
                                   roll: ThrowTiming.quick.landing + .milliseconds(150),
                                   yourRoll: ThrowTiming.full.landing + .milliseconds(150))
        static let instant = Pacing(computer: .zero, step: .zero, roll: .zero, yourRoll: .zero)

        /// Normal pacing, with your throw the full or quick one.
        static func normal(_ style: DiceAnimation) -> Pacing {
            var p = normal
            // Off: the die only fades in, so a short wait is enough to see it.
            p.yourRoll = style == .off ? .milliseconds(400) : ThrowTiming.of(style).landing + .milliseconds(150)
            return p
        }
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
    /// Learn the game, while it runs: the lesson and how it went. Nothing is saved meanwhile.
    private(set) var tutorial: TutorialProgress?
    /// The lesson's own die (its scripted faces), in place of the game's while a lesson runs.
    @ObservationIgnored private var lessonDice: ScriptedDice?
    @ObservationIgnored private let feedback: FeedbackPlayer?
    @ObservationIgnored private var aiSeed: UInt64
    @ObservationIgnored private var aiRolls: UInt64 = 0

    init(store: GameStore = .shared, dice: DiceSource = RandomDice(), feedback: FeedbackPlayer? = nil) {
        self.store = store
        self.dice = dice
        self.feedback = feedback
        setup = GameSetup(seats: [.red: .human, .black: .computer(.novice)])
        state = GameState(players: [.red, .black])
        aiSeed = UInt64.random(in: 0...UInt64.max)
        restoreSaved()
    }

    /// Which game this is. Starting a game or a lesson, or leaving one, moves it on, and anything
    /// still running for an earlier one (a computer's turn, a token's walk) stops instead of playing
    /// into the new board.
    @ObservationIgnored private var generation = 0

    /// A fresh slate for a different game or lesson: earlier turns stop, and nothing of the last
    /// game (its commentary, a chosen token, a token mid-walk) carries over.
    private func startOver() {
        generation &+= 1
        isComputerPlaying = false
        motion = nil
        selectedToken = nil
        log = []
        lastEvents = []
        lastRoll = nil
    }

    /// A game loaded on a computer's turn (the app was closed while it played) carries on by itself.
    private func resumeComputerTurns() {
        guard !state.isOver, case .computer = setup.seat(state.toMove) else { return }
        Task { await runComputerTurns() }
    }

    /// Back to the saved game, if there is one.
    private func restoreSaved() {
        if let saved = store.load() {
            setup = saved.setup
            state = saved.state
            aiSeed = saved.aiSeed
            hasGame = !saved.state.isOver
            resumeComputerTurns()
        } else {
            setup = GameSetup(seats: [.red: .human, .black: .computer(.novice)])
            state = GameState(players: [.red, .black])
            hasGame = false
        }
    }

    // MARK: Learn the game

    /// Starts the tutorial at lesson `index` (a Learn card starts at its chapter's first lesson).
    func startTutorial(at index: Int = 0) {
        tutorial = TutorialProgress(index: max(0, min(Lesson.all.count - 1, index)))
        loadLesson()
    }

    /// The lesson again from its start position.
    func retryLesson() { loadLesson() }

    /// On to the next lesson; false after the last.
    @discardableResult
    func nextLesson() -> Bool {
        guard let t = tutorial, !t.isLast else { return false }
        tutorial = TutorialProgress(index: t.index + 1)
        loadLesson()
        return true
    }

    /// Leaves the tutorial and puts the player's own game back.
    func endTutorial() {
        guard tutorial != nil else { return }
        startOver()
        tutorial = nil
        lessonDice = nil
        restoreSaved()
    }

    private func loadLesson() {
        guard var t = tutorial else { return }
        startOver()
        let lesson = t.lesson
        // Black is a person who is never asked to move: the lesson ends on Red's turn.
        setup = GameSetup(seats: [.red: .human, .black: .human], rules: .ghanaClassic)
        state = GameState.arranged(players: [.red, .black], rules: .ghanaClassic, toMove: .red,
                                   tokens: [.red: lesson.red, .black: lesson.black])
        lessonDice = ScriptedDice(lesson.dice)
        lastRoll = nil
        lastEvents = []
        log = []
        selectedToken = nil
        t.outcome = .playing
        tutorial = t
    }

    /// After a roll or a move in a lesson: done if it did what the lesson asked; otherwise, once
    /// Red's go is over, try again.
    private func checkLesson(_ events: [GameEvent], afterMove: Bool) {
        guard var t = tutorial, t.outcome == .playing else { return }
        if events.contains(where: t.lesson.goal) {
            t.outcome = .done
        } else if afterMove || events.contains(.passed(.red)) {
            t.outcome = .tryAgain
        } else {
            return
        }
        tutorial = t
    }

    /// Starts from an arranged position (UI tests, screenshots).
    func load(_ scenario: Scenario) {
        startOver()
        let (setup, state) = scenario.game
        self.setup = setup
        self.state = state
        lastRoll = nil
        log = []
        hasGame = true
        save()
    }

    func newGame(_ setup: GameSetup) {
        startOver()
        self.setup = setup
        // Against the computer you go first, whichever colour you chose; with friends, the first
        // colour clockwise from red.
        let people = setup.colors.filter { setup.seat($0) == .human }
        state = GameState(players: setup.colors, rules: setup.rules, first: people.count == 1 ? people[0] : nil)
        aiSeed = UInt64.random(in: 0...UInt64.max)
        lastRoll = nil
        lastEvents = []
        hasGame = true
        save()
    }

    private var humanToMove: Bool { setup.seat(state.toMove) == .human }

    /// The person whose turn it is may roll.
    var canRoll: Bool {
        !state.isOver && humanToMove && state.pendingRoll == nil && !isComputerPlaying
            && (tutorial == nil || (tutorial?.outcome == .playing && state.toMove == .red))
    }

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
        // In a lesson you play red; Black only stands on the board.
        if tutorial != nil { return color == .red ? "You" : color.name }
        if let given = setup.names[color] { return given }
        return switch setup.seat(color) {
        case .human: setup.seats.values.filter({ $0 == .human }).count > 1 ? color.name : "You"
        case .computer: color.name
        }
    }

    /// The computers' level, when there are computers (they all play at one level).
    var computerLevel: LudoAIDifficulty? {
        for color in setup.colors { if case let .computer(level) = setup.seat(color) { return level } }
        return nil
    }

    /// The line at the top of the game: whose turn, and the roll in words (the 3D die shows several
    /// faces, so the roll is always said as a number too).
    var status: String {
        let s = state
        if let w = s.winner { return name(w) == "You" ? "You win!" : "\(name(w)) wins" }
        let mover = name(s.toMove)
        let rolled = lastRoll.flatMap { $0.color == s.toMove ? $0.value : nil }
        if isComputerPlaying {
            if let rolled, s.pendingRoll != nil || motion != nil { return "\(mover) rolled \(rolled)" }
            return "\(mover) is playing…"
        }
        if let rolled, s.pendingRoll != nil {
            return "\(mover) rolled \(rolled) · " + (selectedToken != nil ? "choose a move" : "choose a token")
        }
        return mover == "You" ? "Your roll" : "\(mover) to roll"
    }

    /// Changes every computer opponent's level, mid-game; the game carries on from where it is.
    func changeLevel(to level: LudoAIDifficulty) {
        guard computerLevel != nil else { return }
        var seats = setup.seats
        for (color, seat) in seats { if case .computer = seat { seats[color] = .computer(level) } }
        setup = GameSetup(seats: seats, rules: setup.rules)
        save()
    }

    /// Novice games against the computer (owner, 2026-10-04): when your roll leaves one move and it
    /// is a plain move forward, there is nothing to decide, so it plays itself. Never with a choice
    /// (two tokens, or a kick as well), never bringing a token out, never in pass & play or lessons.
    var onlyForwardMove: Move? {
        guard computerLevel == .novice, tutorial == nil, humanToMove, !isComputerPlaying, motion == nil else { return nil }
        let moves = state.legalMoves()
        guard moves.count == 1, moves[0].kind == .forward else { return nil }
        return moves[0]
    }

    func roll() async {
        guard canRoll else { return }
        rollDie()
        if let move = onlyForwardMove {
            let game = generation
            // Let the die land first, so the roll is seen before the token walks.
            if pacing.yourRoll > .zero { try? await Task.sleep(for: pacing.yourRoll) }
            guard game == generation else { return }
            await play(move)   // plays the computers' turns after it
            return
        }
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
        let game = generation
        let mover = state.toMove
        let cells = state.path(for: move)
        if pacing.step > .zero, !cells.isEmpty {
            motion = Motion(color: mover, token: move.token, cells: cells, step: 0)
            for i in cells.indices {
                motion?.step = i
                feedback?.play(.step)
                try? await Task.sleep(for: pacing.step)
                guard game == generation else { return }   // left mid-walk: not this board's move any more
            }
        } else {
            for _ in cells { feedback?.play(.step) }
        }
        guard let events = try? state.apply(move) else { motion = nil; return }
        motion = nil
        lastEvents = events
        describe(events)
        sound(events)
        checkLesson(events, afterMove: true)
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

    // MARK: On and off the screen

    /// Whether the app is on the screen. Off it, computers wait rather than play on unseen (and
    /// keep the app busy in the background); they carry on where they were when it comes back.
    @ObservationIgnored private(set) var isOnScreen = true
    @ObservationIgnored private var waitingForScreen: [CheckedContinuation<Void, Never>] = []

    /// The scene became active (true) or went inactive or to the background (false).
    func setOnScreen(_ on: Bool) {
        guard on != isOnScreen else { return }
        isOnScreen = on
        if on {
            let waiting = waitingForScreen
            waitingForScreen = []
            for w in waiting { w.resume() }
        } else {
            feedback?.suspend()
        }
    }

    private func untilOnScreen() async {
        while !isOnScreen {
            await withCheckedContinuation { waitingForScreen.append($0) }
        }
    }

    /// Lets computer seats play until it is a person's turn or the game is over.
    func runComputerTurns() async {
        guard !isComputerPlaying else { return }
        let game = generation
        isComputerPlaying = true
        // Only this game's loop says it has stopped; a newer game's loop may be running by then.
        defer { if game == generation { isComputerPlaying = false } }
        // After every pause the game is checked again: Home, a new game or a lesson may have come
        // in between, and this loop must not roll or move for them.
        while game == generation, !state.isOver, case let .computer(level) = setup.seat(state.toMove) {
            if pacing.computer > .zero { try? await Task.sleep(for: pacing.computer) }
            await untilOnScreen()
            guard game == generation, !state.isOver, case .computer = setup.seat(state.toMove) else { return }
            if state.pendingRoll == nil {
                rollDie()
                if pacing.roll > .zero { try? await Task.sleep(for: pacing.roll) }
                guard game == generation else { return }
            }
            guard !state.isOver, state.pendingRoll != nil, case .computer = setup.seat(state.toMove) else { continue }
            var rng = SeededGenerator(seed: aiSeed &+ aiRolls)
            aiRolls &+= 1
            // No move for a roll that is waiting can only come from a damaged save: stop rather than
            // spin for ever.
            guard let move = AIPlayer(difficulty: level).chooseMove(state, using: &rng) else { return }
            await perform(move)
        }
    }

    private func rollDie() {
        let color = state.toMove
        let value = (lessonDice ?? dice).roll()
        lastRoll = (color, value)
        rolls += 1
        feedback?.play(.roll)
        lastEvents = state.roll(value)
        describe(lastEvents)
        sound(lastEvents)
        checkLesson(lastEvents, afterMove: false)
        save()
    }

    /// Puts what just happened into words for the log (and VoiceOver).
    private func describe(_ events: [GameEvent]) {
        var kind: Move.Kind = .forward
        func whose(_ c: PlayerColor) -> String { name(c) == "You" ? "your" : "\(name(c))'s" }
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
                line = "\(name(by)) \(verb) \(whose(color)) token back to its yard"
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
        guard tutorial == nil else { return }   // a lesson never replaces the player's own game
        if state.isOver {
            store.clear()
            hasGame = false
        } else {
            store.save(SavedGame(setup: setup, state: state, aiSeed: aiSeed))
        }
    }
}
