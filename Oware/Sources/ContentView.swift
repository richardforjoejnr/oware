import SwiftUI
import OwareEngine

/// Placeholder home screen. Replaced by the real menu in Milestone 2 (see docs/GAME_PLAN.md).
struct ContentView: View {
    private let state = GameState.initial

    var body: some View {
        VStack(spacing: 16) {
            Text("Ɔware")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .accessibilityIdentifier("home-title")
            Text("Akwaaba — welcome")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Seeds on board: \(state.seedsOnBoard)")
                .font(.footnote.monospacedDigit())
                .accessibilityIdentifier("home-seed-count")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
