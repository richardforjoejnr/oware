import SwiftUI

enum Screen: Hashable {
    case home
    case game
}

struct RootView: View {
    @Environment(GameSession.self) private var session
    @State private var screen: Screen = .home
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            switch screen {
            case .home:
                HomeView(startGame: { screen = .game }, openSettings: { showSettings = true })
                    .transition(.opacity)
            case .game:
                GameView(goHome: { screen = .home }, openSettings: { showSettings = true })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: screen)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium])
                .presentationBackground(Theme.ember)
        }
        .statusBarHidden(true)
    }
}
