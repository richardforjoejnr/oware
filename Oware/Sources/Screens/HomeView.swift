import SwiftUI
import OwareEngine
import OwareAI

/// One clear action, nothing else competing. Play (or Continue) is the only large control;
/// Journey sits underneath; everything else lives behind a quiet "More" reveal.
struct HomeView: View {
    @Environment(GameSession.self) private var session
    @Environment(PuzzleLibrary.self) private var library
    @Environment(JourneyProgress.self) private var progress
    @Environment(AppSettings.self) private var settings
    let startGame: () -> Void
    let openPuzzles: () -> Void
    let openHeritage: () -> Void
    let openJourney: () -> Void
    let openSettings: () -> Void

    @AppStorage("preferredDifficulty") private var preferredDifficulty: Int = Difficulty.learner.rawValue
    @AppStorage("tutorialSeen") private var tutorialSeen = false
    @State private var showMore = false
    @State private var showLevels = false

    private var difficulty: Difficulty { Difficulty(rawValue: preferredDifficulty) ?? .learner }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("Lelu Oware")
                    .font(Theme.title(46))
                    .foregroundStyle(Theme.ivory)
                    .accessibilityIdentifier("home-title")
                Text("Akwaaba · welcome")
                    .font(Theme.body(17))
                    .foregroundStyle(Theme.ivoryDim)
            }
            .padding(.bottom, 48)

            primaryAction
                .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 2) {
                QuietButton(title: "Journey", subtitle: progress.totalStars == 0 ? "across Ghana" : "\(progress.totalStars) stars") {
                    openJourney()
                }
                .accessibilityIdentifier("btn-journey")

                if !tutorialSeen {
                    QuietButton(title: "New here?", subtitle: "learn in five minutes") {
                        tutorialSeen = true
                        session.startTutorial(step: 0)
                        startGame()
                    }
                    .accessibilityIdentifier("btn-learn")
                }

                moreToggle

                if showMore {
                    moreItems
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 0)

            Text("Oware · Abapa rules · a game of Ghana")
                .font(Theme.caption())
                .foregroundStyle(Theme.ivoryDim)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: showMore)
        .animation(.easeInOut(duration: 0.2), value: showLevels)
    }

    // MARK: - Primary

    @ViewBuilder
    private var primaryAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.hasResumableGame {
                Button {
                    startGame()
                } label: {
                    primaryLabel("Continue", subtitle: session.mode.title)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-continue")

                QuietButton(title: "New game", subtitle: "against \(difficulty.displayName)") {
                    startNewGame()
                }
                .accessibilityIdentifier("btn-play-ai")
            } else {
                Button {
                    startNewGame()
                } label: {
                    primaryLabel("Play", subtitle: nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-play-ai")

                Button {
                    showLevels.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text("against \(difficulty.displayName)")
                        Image(systemName: showLevels ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .font(Theme.caption(14))
                    .foregroundStyle(Theme.ivoryDim)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn-level")
                .accessibilityLabel("Opponent level, \(difficulty.displayName)")

                if showLevels {
                    levelPicker
                        .transition(.opacity)
                }
            }
        }
    }

    private func primaryLabel(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.title(40))
                .foregroundStyle(Theme.gold)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.caption(14))
                    .foregroundStyle(Theme.ivoryDim)
            }
            Rectangle()
                .fill(Theme.gold.opacity(0.55))
                .frame(width: 56, height: 1)
                .padding(.top, 6)
        }
        .contentShape(Rectangle())
    }

    private func startNewGame() {
        session.newGame(.versusAI(difficulty: difficulty, personality: .balanced, humanPlays: .south), rules: settings.rules)
        startGame()
    }

    private var levelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Difficulty.allCases, id: \.rawValue) { level in
                    Button {
                        preferredDifficulty = level.rawValue
                        showLevels = false
                    } label: {
                        Text(level.displayName)
                            .font(Theme.caption(14))
                            .foregroundStyle(level == difficulty ? Theme.gold : Theme.ivoryDim)
                            .underline(level == difficulty, color: Theme.gold)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("level-\(level.displayName.lowercased())")
                    .accessibilityAddTraits(level == difficulty ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("level-picker")
    }

    // MARK: - More

    private var moreToggle: some View {
        Button {
            showMore.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(showMore ? "Less" : "More")
                    .font(Theme.body(18))
                    .foregroundStyle(Theme.ivoryDim)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ivoryDim)
                    .rotationEffect(.degrees(showMore ? 180 : 0))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("btn-more")
        .accessibilityLabel(showMore ? "Fewer options" : "More options")
    }

    private var moreItems: some View {
        VStack(alignment: .leading, spacing: 2) {
            QuietButton(title: "Pass & Play", subtitle: "two players, one board") {
                session.newGame(.passAndPlay, rules: settings.rules)
                startGame()
            }
            .accessibilityIdentifier("btn-pass-play")

            QuietButton(title: "Riddles", subtitle: library.dailySolved ? "today's solved · \(library.solvedIDs.count) of \(library.puzzles.count)" : "a new one every day") {
                openPuzzles()
            }
            .accessibilityIdentifier("btn-puzzles")

            if tutorialSeen {
                QuietButton(title: "Learn", subtitle: "the five-minute lesson") {
                    session.startTutorial(step: 0)
                    startGame()
                }
                .accessibilityIdentifier("btn-learn")
            }

            QuietButton(title: "Rules & heritage") { openHeritage() }
                .accessibilityIdentifier("btn-heritage")

            QuietButton(title: "Settings") { openSettings() }
                .accessibilityIdentifier("btn-settings")
        }
        .padding(.leading, 2)
    }
}
