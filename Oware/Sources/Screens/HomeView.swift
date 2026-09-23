import SwiftUI
import OwareEngine
import OwareAI

struct HomeView: View {
    @Environment(GameSession.self) private var session
    @Environment(PuzzleLibrary.self) private var library
    let startGame: () -> Void
    let openPuzzles: () -> Void
    let openHeritage: () -> Void
    let openSettings: () -> Void

    @AppStorage("preferredDifficulty") private var preferredDifficulty: Int = Difficulty.player.rawValue

    private var difficulty: Difficulty { Difficulty(rawValue: preferredDifficulty) ?? .player }

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
            .padding(.bottom, 44)

            VStack(alignment: .leading, spacing: 2) {
                if session.hasResumableGame {
                    QuietButton(title: "Continue", subtitle: session.mode.title, prominent: true) {
                        startGame()
                    }
                    .accessibilityIdentifier("btn-continue")
                }

                QuietButton(title: "Play", subtitle: "against \(difficulty.displayName)") {
                    session.newGame(.versusAI(difficulty: difficulty, personality: .balanced, humanPlays: .south))
                    startGame()
                }
                .accessibilityIdentifier("btn-play-ai")

                levelPicker
                    .padding(.bottom, 10)

                QuietButton(title: "Pass & Play", subtitle: "two players, one board") {
                    session.newGame(.passAndPlay)
                    startGame()
                }
                .accessibilityIdentifier("btn-pass-play")

                QuietButton(title: "Learn", subtitle: "a five-minute lesson with Nana") {
                    session.startTutorial(step: 0)
                    startGame()
                }
                .accessibilityIdentifier("btn-learn")

                QuietButton(title: "Riddles", subtitle: library.dailySolved ? "today's solved · \(library.solvedIDs.count) of \(library.puzzles.count)" : "today's riddle waiting") {
                    openPuzzles()
                }
                .accessibilityIdentifier("btn-puzzles")

                QuietButton(title: "Rules & heritage") { openHeritage() }
                    .accessibilityIdentifier("btn-heritage")

                QuietButton(title: "Settings") { openSettings() }
                    .accessibilityIdentifier("btn-settings")
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
    }

    private var levelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Difficulty.allCases, id: \.rawValue) { level in
                    Button {
                        preferredDifficulty = level.rawValue
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
            .padding(.leading, 2)
        }
        .accessibilityIdentifier("level-picker")
    }
}
