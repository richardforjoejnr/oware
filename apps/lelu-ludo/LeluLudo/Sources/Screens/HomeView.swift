import LudoAI
import LudoEngine
import SwiftUI

/// The menu: continue, play the computer, or pass & play.
struct HomeView: View {
    @Environment(LudoSession.self) private var session
    @Environment(AppSettings.self) private var settings
    let startGame: () -> Void
    @State private var showSettings = false
    @State private var opponents = 1
    @State private var level: LudoAIDifficulty = .novice
    @State private var players = 2

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("Lelu Ludo")
                    .font(.system(size: 46, weight: .semibold, design: .serif))
                    .foregroundStyle(Palette.ivory)
                    .padding(.top, 40)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home-title")
                Text("Ludo as it is played in Ghana")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Palette.ivory.opacity(0.75))

                if session.hasGame {
                    menuButton("Continue", id: "btn-continue") { startGame() }
                }

                panel {
                    Text("Play the computer").font(.headline)
                    Stepper("Opponents: \(opponents)", value: $opponents, in: 1...3).accessibilityIdentifier("stepper-opponents")
                    Picker("Level", selection: $level) {
                        ForEach(LudoAIDifficulty.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("picker-level")
                    menuButton("Play", id: "btn-play-computer") {
                        session.newGame(.versusComputer(opponents: opponents, level: level, rules: settings.rules))
                        startGame()
                    }
                }

                panel {
                    Text("Pass & play").font(.headline)
                    Stepper("Players: \(players)", value: $players, in: 2...4).accessibilityIdentifier("stepper-players")
                    menuButton("Play together", id: "btn-pass-play") {
                        session.newGame(.passAndPlay(players: players, rules: settings.rules))
                        startGame()
                    }
                }

                Button {
                    showSettings = true
                } label: {
                    Label("Rules: \(settings.preset.title)", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("btn-settings")
            }
            .padding()
        }
        .foregroundStyle(Palette.ivory)
        .tint(Palette.brass)
        .background(Palette.night.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.wood))
    }

    private func menuButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.brass)
        .foregroundStyle(Palette.night)
        .accessibilityIdentifier(id)
    }
}
