import SwiftUI
import OwareEngine

struct GameView: View {
    @Environment(GameSession.self) private var session
    let goHome: () -> Void
    let openSettings: () -> Void

    @State private var hint: String?
    @State private var hintTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                BoardView(onBlockedTap: showHint)
                    .padding(.horizontal, 6)
                bottomBar
            }
            if session.isGameOver {
                GameOverOverlay(goHome: goHome)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: session.isGameOver)
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
            Text(session.mode.title)
                .font(Theme.caption(14))
                .foregroundStyle(Theme.ivoryDim)
            Spacer()

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

    private var bottomBar: some View {
        ZStack {
            Text(session.turnDescription)
                .font(Theme.body(18))
                .foregroundStyle(session.humanToMove ? Theme.ivory : Theme.ivoryDim)
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
        .frame(height: 56)
        .animation(.easeInOut(duration: 0.25), value: hint)
        .padding(.bottom, 12)
    }

    private func showHint(_ text: String) {
        hint = text
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { hint = nil }
        }
    }
}

struct GameOverOverlay: View {
    @Environment(GameSession.self) private var session
    let goHome: () -> Void

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
            VStack(spacing: 4) {
                QuietButton(title: "Play again", prominent: true) {
                    session.newGame(session.mode)
                }
                .accessibilityIdentifier("btn-play-again")
                QuietButton(title: "Home") { goHome() }
                    .accessibilityIdentifier("btn-home-overlay")
            }
            .frame(maxWidth: 260)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.night.opacity(0.88))
    }
}
