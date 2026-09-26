import SwiftUI
import OwareAI

enum Screen: Hashable {
    case home
    case game
    case puzzles
    case heritage
    case journey
}

struct RootView: View {
    @Environment(GameSession.self) private var session
    @Environment(JourneyProgress.self) private var progress
    @State private var screen: Screen = .home
    @State private var showSettings = false
    /// The carved-map opening; skipped for test launches so suites are not slowed.
    @State private var showSplash = !LaunchOptions.fastAnimations && !LaunchOptions.startGame && LaunchOptions.startScreen == nil

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.6)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
            switch screen {
            case .home:
                HomeView(startGame: { screen = .game },
                         openPuzzles: { screen = .puzzles },
                         openHeritage: { screen = .heritage },
                         openJourney: { screen = .journey },
                         openSettings: { showSettings = true })
                    .transition(.opacity)
            case .game:
                GameView(goHome: { screen = .home },
                         goToPuzzles: { screen = .puzzles },
                         goToJourney: { screen = .journey },
                         openSettings: { showSettings = true })
                    .transition(.opacity)
            case .journey:
                JourneyView(goBack: { screen = .home }, startMatch: { chapter, opponent in
                    session.newGame(.journey(chapter: chapter, opponent: opponent))
                    screen = .game
                })
                .transition(.opacity)
            case .heritage:
                HeritageView(goBack: { screen = .home })
                    .transition(.opacity)
            case .puzzles:
                PuzzlesView(goBack: { screen = .home }, startPuzzle: { puzzle in
                    session.startPuzzle(puzzle)
                    screen = .game
                })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: screen)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationBackground(Theme.ember)
        }
        .statusBarHidden(true)
        .onAppear {
            switch LaunchOptions.startScreen {
            case "journey": screen = .journey
            case "puzzles": screen = .puzzles
            case "heritage": screen = .heritage
            default: break
            }
            if LaunchOptions.startGame, screen == .home {
                session.newGame(.versusAI(difficulty: .learner, personality: .balanced, humanPlays: .south))
                screen = .game
                #if DEBUG
                if let n = LaunchOptions.demoStores {
                    Task { try? await Task.sleep(for: .milliseconds(300)); session.loadDemoPosition(storeSeeds: n) }
                }
                #endif
                if LaunchOptions.demoMove {
                    Task { try? await Task.sleep(for: .seconds(2)); session.play(house: 0) }
                }
            }
        }
    }
}
