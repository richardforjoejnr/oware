import SwiftUI
import OwareEngine
import OwareAI

struct GameView: View {
    @Environment(GameSession.self) private var session
    @Environment(PuzzleLibrary.self) private var library
    @Environment(JourneyProgress.self) private var progress
    @Environment(AppSettings.self) private var settings
    let goHome: () -> Void
    var goToPuzzles: () -> Void = {}
    var goToJourney: () -> Void = {}
    let openSettings: () -> Void

    @State private var hint: String?
    @State private var hintTask: Task<Void, Never>?
    @State private var showLevels = false
    @AppStorage("preferredDifficulty") private var preferredDifficulty: Int = Difficulty.learner.rawValue

    var body: some View {
        ZStack {
            LinearGradient(colors: [settings.boardTheme.backgroundTop, settings.boardTheme.backgroundBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if showLevels, session.canChangeDifficulty {
                    levelRow
                        .transition(.opacity)
                }
                BoardView(onBlockedTap: { showHint($0) })
                    .padding(.horizontal, 6)
                bottomBar
            }
            if session.isGameOver && session.mode.isResumable {
                GameOverOverlay(goHome: goHome, goToJourney: goToJourney)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: session.isGameOver)
        .onChange(of: session.isGameOver) { _, over in
            if over, let opponent = session.mode.journeyOpponent {
                progress.record(stars: Journey.stars(for: session.state), for: opponent)
            }
        }
        .onAppear {
            if let opponent = session.mode.journeyOpponent, session.state.moveNumber == 0 {
                showHint(opponent.greeting, seconds: 3.5)
            }
        }
        .onChange(of: session.puzzleAttempt) { _, attempt in
            if attempt == .solved, let puzzle = session.currentPuzzle { library.markSolved(puzzle) }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: goHome) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ivoryDim)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("btn-home")
            .accessibilityLabel("Home")

            Spacer()
            if session.canChangeDifficulty {
                Button {
                    showLevels.toggle()
                } label: {
                    opponentStrip(chevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-mode-title")
                .accessibilityLabel("Opponent level, \(session.mode.title). Tap to change")
            } else {
                opponentStrip(chevron: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("mode-title")
            }
            Spacer()

            if session.mode.isResumable {
                Button(action: { session.requestHint() }) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(session.canHint ? Theme.ivoryDim : Theme.ivoryDim.opacity(0.3))
                        .frame(width: 44, height: 44)
                }
                .disabled(!session.canHint)
                .accessibilityIdentifier("btn-hint")
                .accessibilityLabel("Hint")
            }

            Button(action: { session.undo() }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(session.canUndo ? Theme.ivoryDim : Theme.ivoryDim.opacity(0.3))
                    .frame(width: 44, height: 44)
            }
            .disabled(!session.canUndo)
            .accessibilityIdentifier("btn-undo")
            .accessibilityLabel("Undo")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    /// Who you are playing: a small badge, their name and their captured seeds.
    private func opponentStrip(chevron: Bool) -> some View {
        let opponentSide: Player = session.mode.aiSide ?? .north
        let seeds = session.state.store(of: opponentSide)
        let active = !session.isGameOver && session.state.sideToMove == opponentSide
        return HStack(spacing: 10) {
            badge(letter: String(session.opponentName.prefix(1)), active: active)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.opponentName)
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.ivory)
                    if chevron {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.ivoryDim)
                            .rotationEffect(.degrees(showLevels ? 180 : 0))
                    }
                }
                Text(session.mode.isResumable ? "\(seeds) seeds" + (session.opponentRole.map { " · \($0)" } ?? "") : session.mode.title)
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ivoryDim)
            }
        }
        .contentShape(Rectangle())
    }

    private func badge(letter: String, active: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Theme.ember)
                .overlay(Circle().stroke(active ? Theme.gold : Theme.ivoryDim.opacity(0.35), lineWidth: active ? 1.5 : 1))
            Text(letter)
                .font(Theme.body(15))
                .foregroundStyle(active ? Theme.gold : Theme.ivoryDim)
        }
        .frame(width: 30, height: 30)
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    /// Inline level picker under the top bar; changes the running game's opponent.
    private var levelRow: some View {
        HStack(spacing: 18) {
            ForEach(Difficulty.allCases, id: \.rawValue) { level in
                let current: Bool = {
                    if case let .versusAI(d, _, _) = session.mode { return d == level }
                    return false
                }()
                Button {
                    session.changeDifficulty(to: level)
                    preferredDifficulty = level.rawValue
                    showLevels = false
                    showHint("Now playing against \(level.displayName)")
                } label: {
                    Text(level.displayName)
                        .font(Theme.caption(13))
                        .foregroundStyle(current ? Theme.gold : Theme.ivoryDim)
                        .underline(current, color: Theme.gold)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("game-level-\(level.displayName.lowercased())")
                .accessibilityAddTraits(current ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: showLevels)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if session.mode.isResumable {
                youStrip
            }
            ZStack {
                Text(session.turnDescription)
                    .font(Theme.body(session.mode.isResumable ? 18 : 16))
                    .foregroundStyle(session.humanToMove ? Theme.ivory : Theme.ivoryDim)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("turn-indicator")
                    .opacity(hint == nil ? 1 : 0)
                if let hint {
                    Text(hint)
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.gold)
                        .transition(.opacity)
                        .accessibilityIdentifier("hint")
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 24)
            modeControls
        }
        .frame(minHeight: 56)
        .animation(.easeInOut(duration: 0.25), value: hint)
        .animation(.easeInOut(duration: 0.3), value: session.puzzleAttempt)
        .animation(.easeInOut(duration: 0.3), value: session.tutorialStepDone)
        .padding(.bottom, 12)
    }

    private var youStrip: some View {
        let mine = session.state.store(of: .south)
        let active = !session.isGameOver && session.state.sideToMove == .south && session.mode.aiSide != .south
        let name: String = {
            if case .passAndPlay = session.mode { return session.state.sideToMove == .south ? "A" : "B" }
            return "You"
        }()
        let seeds: Int = {
            if case .passAndPlay = session.mode { return session.state.store(of: session.state.sideToMove) }
            return mine
        }()
        return HStack(spacing: 10) {
            badge(letter: String(name.prefix(1)), active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.ivory)
                Text("\(seeds) seeds")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ivoryDim)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("you-strip")
    }

    /// Puzzle and tutorial controls under the board; nothing for ordinary games.
    @ViewBuilder
    private var modeControls: some View {
        if let puzzle = session.currentPuzzle {
            HStack(spacing: 28) {
                if session.puzzleAttempt == .solved {
                    if let next = library.next(after: puzzle) {
                        smallButton("Next riddle", id: "btn-next-puzzle", prominent: true) { session.startPuzzle(next) }
                    }
                    smallButton("All riddles", id: "btn-all-puzzles") { goToPuzzles() }
                } else {
                    Text("Goal: \(puzzle.target) seeds")
                        .font(Theme.caption())
                        .foregroundStyle(Theme.ivoryDim)
                        .accessibilityIdentifier("puzzle-goal")
                    if case .wrong = session.puzzleAttempt {
                        smallButton("Reset", id: "btn-retry") { session.retryPuzzle() }
                    }
                }
            }
            .frame(height: 32)
        } else if let step = session.currentTutorialStep, case let .tutorial(index) = session.mode {
            VStack(spacing: 8) {
                if session.tutorialStepDone, let after = step.afterText {
                    Text(after)
                        .font(Theme.caption(14))
                        .foregroundStyle(Theme.gold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier("tutorial-after")
                }
                HStack(spacing: 28) {
                    HStack(spacing: 6) {
                        ForEach(0..<Tutorial.steps.count, id: \.self) { i in
                            Circle()
                                .fill(i <= index ? Theme.gold : Theme.ivoryDim.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Step \(index + 1) of \(Tutorial.steps.count)")
                    .accessibilityIdentifier("tutorial-progress")
                    if session.tutorialStepDone {
                        if index + 1 < Tutorial.steps.count {
                            smallButton("Next", id: "btn-next-step", prominent: true) { session.advanceTutorial() }
                        } else {
                            smallButton("Play", id: "btn-tutorial-play", prominent: true) {
                                session.newGame(.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south))
                            }
                        }
                    }
                }
                .frame(height: 32)
            }
        }
    }

    private func smallButton(_ title: String, id: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(17))
                .foregroundStyle(prominent ? Theme.gold : Theme.ivoryDim)
                .padding(.horizontal, 6)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func showHint(_ text: String, seconds: Double = 1.6) {
        hint = text
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { hint = nil }
        }
    }
}

struct GameOverOverlay: View {
    @Environment(GameSession.self) private var session
    @Environment(JourneyProgress.self) private var progress
    @Environment(StoreManager.self) private var store
    let goHome: () -> Void
    var goToJourney: () -> Void = {}
    @State private var showUnlock = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Text(session.turnDescription)
                .font(Theme.title(34))
                .foregroundStyle(Theme.ivory)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("game-over-title")
            Text("\(session.state.store(of: .south)) – \(session.state.store(of: .north))")
                .font(Theme.body(22))
                .foregroundStyle(Theme.gold)
                .accessibilityIdentifier("game-over-score")
            if case let .journey(chapter, index) = session.mode {
                let stars = Journey.stars(for: session.state)
                Text(String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars))
                    .font(Theme.title(30))
                    .foregroundStyle(Theme.gold)
                    .accessibilityIdentifier("journey-result-stars")
                    .accessibilityLabel("\(stars) stars")
                VStack(spacing: 4) {
                    if stars > 0, let next = nextJourneyMatch(after: chapter, index) {
                        if JourneyProgress.requiresPurchase(chapterIndex: next.chapter) && !store.hasFullJourney {
                            QuietButton(title: "Unlock the full Journey", subtitle: Journey.chapter(next.chapter)?.title, prominent: true) {
                                showUnlock = true
                            }
                            .accessibilityIdentifier("btn-unlock-next")
                        } else {
                            QuietButton(title: "Next: \(next.opponent.name)", subtitle: next.opponent.role, prominent: true) {
                                session.newGame(.journey(chapter: next.chapter, opponent: next.index))
                            }
                            .accessibilityIdentifier("btn-next-opponent")
                        }
                    }
                    QuietButton(title: "Play again", prominent: stars == 0) { session.newGame(session.mode) }
                        .accessibilityIdentifier("btn-play-again")
                    QuietButton(title: "Journey") { goToJourney() }
                        .accessibilityIdentifier("btn-journey-overlay")
                }
                .frame(maxWidth: 260)
            } else {
                VStack(spacing: 4) {
                    QuietButton(title: "Play again", prominent: true) {
                        session.newGame(session.mode)
                    }
                    .accessibilityIdentifier("btn-play-again")
                    QuietButton(title: "Home") { goHome() }
                        .accessibilityIdentifier("btn-home-overlay")
                }
                .frame(maxWidth: 260)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.night.opacity(0.88))
        .sheet(isPresented: $showUnlock) {
            UnlockView()
                .presentationDetents([.large])
                .presentationBackground(Theme.ember)
        }
    }
}


private func nextJourneyMatch(after chapter: Int, _ index: Int) -> (chapter: Int, index: Int, opponent: Journey.Opponent)? {
    if let same = Journey.opponent(chapter: chapter, index: index + 1) { return (chapter, index + 1, same) }
    if let next = Journey.opponent(chapter: chapter + 1, index: 0) { return (chapter + 1, 0, next) }
    return nil
}
