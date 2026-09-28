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
    @State private var showRiddle = false
    @State private var showLesson = false
    @State private var showEndGame = false
    private var hasFullText: Bool { session.currentPuzzle != nil || session.currentTutorialStep != nil }
    @AppStorage("preferredDifficulty") private var preferredDifficulty: Int = Difficulty.beginner.rawValue

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Image("ground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
            LinearGradient(colors: [settings.boardTheme.backgroundTop.opacity(0.25), settings.boardTheme.backgroundBottom.opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            // The board takes the whole width; the two thin bars float over its ends.
            VStack(spacing: 0) {
                // The bars around the board have a fixed height: let their text grow a little, not a lot.
                topBar
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                if showLevels, session.canChangeDifficulty {
                    levelRow
                        .transition(.opacity)
                }
                // Long enough to read why the tap was refused (and for UI tests on slow simulators to see it).
                BoardView(onBlockedTap: { showHint($0, seconds: 3) })
                bottomBar
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
            if session.isGameOver && session.mode.isResumable {
                GameOverOverlay(goHome: goHome, goToJourney: goToJourney)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: session.isGameOver)
        .onChange(of: session.isGameOver) { _, over in
            guard over else { return }
            if let opponent = session.mode.journeyOpponent, case let .journey(chapter, _) = session.mode {
                let wasComplete = progress.isComplete(chapterIndex: chapter)
                progress.record(stars: Journey.stars(for: session.state), for: opponent)
                let completed = !wasComplete && progress.isComplete(chapterIndex: chapter)
                PlayerEvents.shared.journeyProgress(totalStars: progress.totalStars, chapterCompleted: completed ? chapter : nil)
            }
            PlayerEvents.shared.gameFinished(mode: session.mode, state: session.state)
        }
        .onAppear {
            if let opponent = session.mode.journeyOpponent, session.state.moveNumber == 0 {
                showHint(opponent.greeting, seconds: 3.5)
            }
        }
        .onChange(of: session.roundMessage) { _, message in
            if let message { showHint(message, seconds: 4.5) }
        }
        .onChange(of: session.puzzleAttempt) { _, attempt in
            if attempt == .solved, let puzzle = session.currentPuzzle {
                let daily = library.isDaily(puzzle)
                library.markSolved(puzzle)
                PlayerEvents.shared.riddleSolved(puzzle, daily: daily, streak: library.currentStreak())
            }
        }
        .sheet(isPresented: $showRiddle) {
            if let puzzle = session.currentPuzzle {
                RiddleCard(puzzle: puzzle, number: library.puzzles(of: puzzle.kind).firstIndex(of: puzzle).map { $0 + 1 })
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.ember)
            }
        }
        .confirmationDialog(endGameTitle, isPresented: $showEndGame, titleVisibility: .visible) {
            endGameButtons
        } message: {
            Text(endGameMessage)
        }
        .sheet(isPresented: $showLesson) {
            if let step = session.currentTutorialStep, case let .tutorial(index) = session.mode {
                LessonCard(step: step, number: index + 1, count: session.tutorialSteps.count, done: session.tutorialStepDone)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.ember)
            }
        }
    }

    /// Home, the opponent, then Hint and Undo: small glass controls, nothing else.
    private var topBar: some View {
        HStack(spacing: 10) {
            roundButton(systemName: "chevron.left", id: "btn-home", label: "Home", enabled: true, action: goHome)

            Spacer(minLength: 0)
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
            Spacer(minLength: 0)

            if session.mode.isResumable {
                Button(action: { session.requestHint() }) {
                    AdinkraGlyph(shape: Adinkra.Nyansapo(), size: 19,
                                 color: session.canHint ? Theme.bone : Theme.ivoryDim.opacity(0.4))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .hudChrome(Circle())
                .disabled(!session.canHint)
                .accessibilityIdentifier("btn-hint")
                .accessibilityLabel("Hint")
            }
            Button(action: { session.undo() }) {
                AdinkraGlyph(shape: Adinkra.Sankofa(), size: 21,
                             color: session.canUndo ? Theme.bone : Theme.ivoryDim.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hudChrome(Circle())
            .disabled(!session.canUndo)
            .accessibilityIdentifier("btn-undo")
            .accessibilityLabel("Undo")
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
    }

    // MARK: Ending a game

    private var isNamNam: Bool { session.state.rules.variant == .namNam }
    private var endGameTitle: String { isNamNam ? "End the game or the round?" : "End the game?" }
    private var endGameMessage: String {
        let stop = isNamNam
            ? "Ending the round: each player keeps the seeds on their own side and houses are shared out."
            : "Stopping here: each player keeps the seeds on their own side and the scores decide."
        return "Resigning gives the game to the other side. " + stop
    }

    @ViewBuilder private var endGameButtons: some View {
        if case .passAndPlay = session.mode {
            Button("A resigns (B wins)", role: .destructive) { session.resign(.south) }
            Button("B resigns (A wins)", role: .destructive) { session.resign(.north) }
        } else {
            Button("Resign (\(session.opponentName) wins)", role: .destructive) { session.resign() }
        }
        Button(isNamNam ? "End this round" : "Stop here and count") { session.agreeToStop() }
        Button("Keep playing", role: .cancel) {}
    }

    private func roundButton(systemName: String, id: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? Theme.bone : Theme.ivoryDim.opacity(0.4))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hudChrome(Circle())
        .disabled(!enabled)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
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
                        .font(Theme.sans(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.ivory)
                    kenteMark(active: active)
                    if chevron {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.ivoryDim)
                            .rotationEffect(.degrees(showLevels ? 180 : 0))
                    }
                }
                seedLine(session.mode.isResumable ? "\(seeds)" + housesNote(opponentSide) + (session.opponentRole.map { " · \($0)" } ?? "") : session.mode.title,
                         showSeed: session.mode.isResumable)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .hudChrome(Capsule())
        .contentShape(Capsule())
    }

    /// "12 seeds" with a small seed drawn before the number.
    private func seedLine(_ text: String, showSeed: Bool) -> some View {
        HStack(spacing: 5) {
            if showSeed {
                Image("seed2")
                    .resizable()
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Theme.caption(12))
                .foregroundStyle(Theme.ivoryDim)
        }
    }

    /// Three tiny Kente dots: the only colour on the HUD, and it marks whose turn it is.
    private func kenteMark(active: Bool) -> some View {
        HStack(spacing: 3) {
            Circle().fill(Theme.kenteRed)
            Circle().fill(Theme.gold)
            Circle().fill(Theme.kenteGreen)
        }
        .frame(width: 22, height: 5)
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: active)
        .accessibilityHidden(true)
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
        .frame(width: 28, height: 28)
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    /// Inline level picker under the top bar; changes the running game's opponent.
    private var levelRow: some View {
        HStack(spacing: 16) {
            ForEach(Difficulty.menuLevels, id: \.rawValue) { level in
                let current: Bool = {
                    if case let .versusAI(d, _, _) = session.mode { return d.menuLevel == level }
                    return false
                }()
                Button {
                    session.changeDifficulty(to: level)
                    preferredDifficulty = level.rawValue
                    showLevels = false
                    showHint("Now playing against \(level.displayName)")
                } label: {
                    Text(level.displayName)
                        .lineLimit(1)
                        .fixedSize()
                        .font(Theme.caption(13))
                        .foregroundStyle(current ? Theme.gold : Theme.ivoryDim)
                        .underline(current, color: Theme.gold)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("game-level-\(level.displayName.lowercased())")
                .accessibilityAddTraits(current ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .hudChrome(Capsule())
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.2), value: showLevels)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            modeControls
            HStack(spacing: 10) {
                if session.mode.isResumable {
                    youStrip
                }
                // End the game or the round: beside your name, where the top bar has no room left.
                if session.canEndGame {
                    roundButton(systemName: "flag", id: "btn-end-game", label: "End game", enabled: true) { showEndGame = true }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                if hasFullText {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.gold)
                        .accessibilityHidden(true)
                }
                ZStack(alignment: .trailing) {
                    Text(session.turnDescription)
                        .font(Theme.serifText(16, weight: .medium, relativeTo: .callout))
                        .foregroundStyle(session.humanToMove ? Theme.ivory : Theme.ivoryDim)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("turn-indicator")
                        .opacity(hint == nil ? 1 : 0)
                    if let hint {
                        Text(hint)
                            .font(Theme.serifText(15, weight: .medium, relativeTo: .subheadline))
                            .foregroundStyle(Theme.gold)
                            .multilineTextAlignment(.trailing)
                            .transition(.opacity)
                            .accessibilityIdentifier("hint")
                    }
                }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .hudChrome(Capsule())
                .lineLimit(1)
                // In a riddle or a lesson, tap the line to read all of it.
                .overlay {
                    if session.currentPuzzle != nil {
                        Button { showRiddle = true } label: { Color.clear.contentShape(Capsule()) }
                            .accessibilityLabel("Read the full riddle")
                            .accessibilityIdentifier("btn-riddle-info")
                    } else if session.currentTutorialStep != nil {
                        Button { showLesson = true } label: { Color.clear.contentShape(Capsule()) }
                            .accessibilityLabel("Read the whole lesson step")
                            .accessibilityIdentifier("btn-lesson-info")
                    }
                }
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 10)
        .padding(.top, 3)
        .padding(.bottom, 2)
        .animation(.easeInOut(duration: 0.25), value: hint)
        .animation(.easeInOut(duration: 0.3), value: session.puzzleAttempt)
        .animation(.easeInOut(duration: 0.3), value: session.tutorialStepDone)
    }

    private var passAndPlaySide: Player? {
        if case .passAndPlay = session.mode { return session.state.sideToMove }
        return nil
    }

    /// Nam-Nam: how many houses this player holds this round.
    private func housesNote(_ player: Player) -> String {
        guard session.state.rules.variant == .namNam else { return "" }
        return " · \(session.state.houses(of: player).count) houses"
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
        return HStack(spacing: 8) {
            badge(letter: String(name.prefix(1)), active: active)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(name)
                        .font(Theme.sans(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.ivory)
                    kenteMark(active: active)
                }
                seedLine("\(seeds) seeds" + housesNote(passAndPlaySide ?? .south), showSeed: true)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .hudChrome(Capsule())
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
                        .foregroundStyle(Theme.onPhoto)
                        .accessibilityIdentifier("puzzle-goal")
                    if case .wrong = session.puzzleAttempt {
                        smallButton("Reset", id: "btn-retry") { session.retryPuzzle() }
                    }
                }
            }
            .frame(minHeight: 32)
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
                        ForEach(0..<session.tutorialSteps.count, id: \.self) { i in
                            Circle()
                                .fill(i <= index ? Theme.gold : Theme.ivoryDim.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityElement()
                    .accessibilityLabel("Step \(index + 1) of \(session.tutorialSteps.count)")
                    .accessibilityIdentifier("tutorial-progress")
                    if session.tutorialStepDone {
                        if index + 1 < session.tutorialSteps.count {
                            smallButton("Next", id: "btn-next-step", prominent: true) { session.advanceTutorial() }
                        } else {
                            smallButton("Play", id: "btn-tutorial-play", prominent: true) {
                                session.newGame(.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south), rules: settings.rules)
                            }
                        }
                    }
                }
                .frame(minHeight: 32)
            }
        }
    }

    private func smallButton(_ title: String, id: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(17))
                .foregroundStyle(prominent ? Theme.gold : Theme.ivoryDim)
                .padding(.horizontal, 6)
                .frame(minHeight: 32)
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
    let goHome: () -> Void
    var goToJourney: () -> Void = {}

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
                        QuietButton(title: "Next: \(next.opponent.name)", subtitle: next.opponent.role, prominent: true) {
                            session.newGame(.journey(chapter: next.chapter, opponent: next.index))
                        }
                        .accessibilityIdentifier("btn-next-opponent")
                    }
                    QuietButton(title: "Play again", prominent: stars == 0) { session.newGame(session.mode) }
                        .accessibilityIdentifier("btn-play-again")
                    QuietButton(title: "Journey") { goToJourney() }
                        .accessibilityIdentifier("btn-journey-overlay")
                    if stars > 0, nextJourneyMatch(after: chapter, index) == nil {
                        // The end of the Journey: point to the newsletter for new chapters.
                        Link(destination: Links.newsletter) {
                            Text("Hear about new chapters")
                                .font(Theme.body(16))
                                .foregroundStyle(Theme.gold)
                        }
                        .padding(.top, 8)
                        .accessibilityIdentifier("btn-newsletter-journey")
                    }
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
    }
}


private func nextJourneyMatch(after chapter: Int, _ index: Int) -> (chapter: Int, index: Int, opponent: Journey.Opponent)? {
    if let same = Journey.opponent(chapter: chapter, index: index + 1) { return (chapter, index + 1, same) }
    if let next = Journey.opponent(chapter: chapter + 1, index: 0) { return (chapter + 1, 0, next) }
    return nil
}
