import LudoAI
import LudoEngine
import SwiftUI

/// The menu, after the owner's art: the carved LELU LUDO plaque, wooden tiles (Start Game, Friends,
/// Settings) and the board in its box on a sand table.
struct HomeView: View {
    @Environment(LudoSession.self) private var session
    @Environment(AppSettings.self) private var settings
    let startGame: () -> Void
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case computer, friends, settings
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(Art.menuTitle)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 420)
                    .accessibilityLabel("Lelu Ludo")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home-title")
                    .padding(.top, 12)

                if session.hasGame {
                    Button { startGame() } label: {
                        Label("Continue your game", systemImage: "play.fill")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(Palette.ivory)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .woodPanel(corner: 27)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn-continue")
                }

                HStack(spacing: 12) {
                    tile(Art.tileStart, label: "Start game against the computer", id: "tile-start") { sheet = .computer }
                    tile(Art.tileFriends, label: "Play with friends on this phone", id: "tile-friends") { sheet = .friends }
                    tile(Art.tileSettings, label: "Settings. Rules: \(settings.preset.title)", id: "btn-settings") { sheet = .settings }
                }

                Image(Art.boardBox)
                    .resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
                    .accessibilityHidden(true)

                Text("\(settings.preset.title) rules")
                    .font(.system(.footnote, design: .serif).weight(.semibold))
                    .foregroundStyle(Palette.wood)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Palette.ivory.opacity(0.55)))
            }
            .padding()
        }
        .background(Table())
        .sheet(item: $sheet) { which in
            switch which {
            case .computer: ComputerGameSheet(startGame: startGame)
            case .friends: FriendsGameSheet(startGame: startGame)
            case .settings: SettingsView()
            }
        }
    }

    private func tile(_ image: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(image).resizable().scaledToFit()
                .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// You against 1–3 computers: how many, and how strong.
struct ComputerGameSheet: View {
    @Environment(LudoSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let startGame: () -> Void
    @State private var opponents = 1
    @State private var level: LudoAIDifficulty = .novice

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Opponents: \(opponents)", value: $opponents, in: 1...3).accessibilityIdentifier("stepper-opponents")
                Picker("Level", selection: $level) {
                    ForEach(LudoAIDifficulty.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("picker-level")
                Section {
                    Button("Play") {
                        session.newGame(.versusComputer(opponents: opponents, level: level, rules: settings.rules))
                        dismiss()
                        startGame()
                    }
                    .font(.headline)
                    .accessibilityIdentifier("btn-play-computer")
                } footer: {
                    Text("\(settings.preset.title) rules. You are red.")
                }
            }
            .navigationTitle("Start game")
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .presentationDetents([.medium])
        .tint(Palette.brass)
    }
}

/// 2–4 people passing one phone.
struct FriendsGameSheet: View {
    @Environment(LudoSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let startGame: () -> Void
    @State private var players = 2

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Players: \(players)", value: $players, in: 2...4).accessibilityIdentifier("stepper-players")
                Section {
                    Button("Play together") {
                        session.newGame(.passAndPlay(players: players, rules: settings.rules))
                        dismiss()
                        startGame()
                    }
                    .font(.headline)
                    .accessibilityIdentifier("btn-pass-play")
                } footer: {
                    Text("\(settings.preset.title) rules. Pass the phone on each turn.")
                }
            }
            .navigationTitle("Friends")
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .presentationDetents([.medium])
        .tint(Palette.brass)
    }
}
