import SwiftUI
import UIKit
import MatchKitNearby
import OwareEngine

/// Play nearby (NEARBY_PLAY_REDESIGN.md §2): one screen. Games nearby turn up by themselves while it
/// is open, or Start nearby game makes yours; then Ready to play on both phones. The game itself is
/// the usual game screen. Never "host", "join mode" or "client" in the player's words.
struct NearbyView: View {
    @Environment(NearbyLobby.self) private var lobby
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    /// The demo player, Ama, instead of real phones.
    let demo: Bool
    let goBack: () -> Void

    @State private var starter: NearbyLobby.Starter = .creatorStarts
    /// Nil until chosen here: the rules from Settings.
    @State private var variant: RuleSet.Variant?
    @State private var name = NearbyLobby.savedName() ?? ""
    @State private var showHelp = false

    private var rules: RuleSet { (variant ?? settings.rules.variant) == .namNam ? .namNam : .abapa }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ivoryDim)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("btn-back")
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(Theme.title(34))
                            .foregroundStyle(Theme.ivory)
                            .accessibilityIdentifier("nearby-title")
                        if lobby.phase == .lobby {
                            Text("Two phones. One game. No internet needed. Stay close and keep Wi-Fi on.")
                                .font(Theme.caption(15))
                                .foregroundStyle(Theme.ivoryDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if demo {
                        Text("Demo: \(DemoPlayer.name) plays on a pretend phone inside this one, the way a friend's phone would.")
                            .font(Theme.caption(14))
                            .foregroundStyle(Theme.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if lobby.status == .localNetworkDenied {
                        localNetworkOff
                    }
                    content
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.night.ignoresSafeArea())
        .font(Theme.body())
        .foregroundStyle(Theme.ivory)
        .tint(Theme.gold)
        .sheet(isPresented: $showHelp) {
            NearbyHelp()
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.ember)
        }
    }

    private var title: String {
        switch lobby.phase {
        case .lobby, .playing, .refused: "Play nearby"
        case .waiting: "Your game is ready"
        case .ready: "Ready to play"
        }
    }

    @ViewBuilder private var content: some View {
        switch lobby.phase {
        case .lobby, .playing:
            startGame
            gamesNearby
            helpLink("How nearby play works")
        case .waiting:
            waiting
        case .ready:
            readyToPlay
        case let .refused(reason):
            VStack(alignment: .leading, spacing: 14) {
                Text(reason)
                    .foregroundStyle(Theme.gold)
                    .accessibilityIdentifier("nearby-refused")
                QuietButton(title: "Back") { lobby.cancel() }
                    .accessibilityIdentifier("btn-cancel")
            }
        }
    }

    // MARK: A. Start nearby game, games nearby

    private var startGame: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Rules") {
                Picker("Rules", selection: Binding(get: { rules.variant }, set: { variant = $0 })) {
                    Text("Abapa").tag(RuleSet.Variant.abapa)
                    Text("Nam-Nam").tag(RuleSet.Variant.namNam)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("nearby-rules")
            }
            VStack(alignment: .leading, spacing: 8) {
                label("Who starts")
                Picker("Who starts", selection: $starter) {
                    ForEach(NearbyLobby.Starter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("nearby-starter")
            }
            row("Nearby name") {
                TextField(NearbyLobby.myName(saved: nil, gameCenter: GameCenter.shared.playerName), text: $name)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .onChange(of: name) { _, name in NearbyLobby.saveName(name) }
                    .accessibilityIdentifier("nearby-name-field")
            }
            QuietButton(title: "Start nearby game", subtitle: "\(NearbyLobby.rulesName(rules)) rules", prominent: true) {
                lobby.start(name: NearbyLobby.myName, rules: rules, starter: starter, pace: settings.effectiveSpeed)
            }
            .accessibilityIdentifier("btn-start-nearby")
        }
        .padding(16)
        .background(Theme.ember, in: RoundedRectangle(cornerRadius: 14))
    }

    private var gamesNearby: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Games nearby")
            if lobby.games.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    WaitingMark()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No games nearby yet")
                            .accessibilityIdentifier("nearby-looking")
                        Text("Ask your friend to start a nearby game.")
                            .font(Theme.caption(14))
                            .foregroundStyle(Theme.ivoryDim)
                    }
                }
            } else {
                ForEach(lobby.games) { game in
                    gameCard(game)
                }
            }
        }
    }

    /// C. A game found nearby: "Ama's game", "Abapa · Ama starts", Join game.
    private func gameCard(_ game: NearbyListing) -> some View {
        let note = [game.rules, game.creatorStarts.map { NearbyLobby.startNote(creatorStarts: $0, creatorName: game.creatorName) }]
            .compactMap { $0 }.joined(separator: " · ")
        return Button {
            lobby.join(game, name: NearbyLobby.myName, pace: settings.effectiveSpeed)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name).font(Theme.body(20))
                    if !note.isEmpty {
                        Text(note)
                            .font(Theme.caption(14))
                            .foregroundStyle(Theme.ivoryDim)
                    }
                }
                Spacer()
                Text("Join game")
                    .font(Theme.body(17))
                    .foregroundStyle(Theme.gold)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wood, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.name), \(note)")
        .accessibilityHint("Join game")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("nearby-game-\(game.name)")
    }

    // MARK: B. Your game is ready

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                WaitingMark()
                Text("Looking for another player nearby…")
                    .accessibilityIdentifier("nearby-waiting")
            }
            VStack(alignment: .leading, spacing: 10) {
                detail("Rules", NearbyLobby.rulesName(rules))
                detail("Who starts", lobby.startedWith == .creatorStarts ? "You" : lobby.startedWith.title)
                detail("Your name", NearbyLobby.myName)
            }
            .padding(16)
            .background(Theme.ember, in: RoundedRectangle(cornerRadius: 14))
            QuietButton(title: "Cancel") { lobby.cancel() }
                .accessibilityIdentifier("btn-cancel")
            helpLink("Can't find each other?")
        }
    }

    // MARK: D. Ready to play

    private var readyToPlay: some View {
        let mine: Player = lobby.isCreator ? .south : .north
        return VStack(alignment: .leading, spacing: 16) {
            playerTile(name: NearbyLobby.myName, side: mine, status: lobby.iAmReady ? "Ready" : "Connected",
                       ready: lobby.iAmReady, isMe: true)
            if let opponent = lobby.opponent {
                playerTile(name: opponent.name, side: mine == .south ? .north : .south,
                           status: status(of: opponent), ready: opponent.isReady, isMe: false)
                if lobby.canSayNotNow {
                    Button("Not now") { Task { await lobby.notNow() } }
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.ivoryDim)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("btn-not-now")
                        .accessibilityLabel("Not now, \(opponent.name)")
                }
            }
            if !lobby.gameNote.isEmpty {
                Text(lobby.gameNote)
                    .font(Theme.caption(15))
                    .foregroundStyle(Theme.ivoryDim)
                    .accessibilityIdentifier("nearby-game-note")
            }
            if lobby.iAmReady {
                HStack(spacing: 12) {
                    WaitingMark()
                    Text("Waiting for \(lobby.opponent?.name ?? NearbyLobby.otherPlayer)…")
                }
            }
            Button { Task { await lobby.ready() } } label: {
                Text("Ready")
                    .font(Theme.body(22))
                    .foregroundStyle(Theme.night)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.gold.opacity(lobby.canPressReady ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!lobby.canPressReady)
            .accessibilityIdentifier("btn-ready")
            QuietButton(title: "Cancel") { lobby.cancel() }
                .accessibilityIdentifier("btn-cancel")
        }
        .animation(.easeInOut(duration: 0.25), value: lobby.opponent)
    }

    private func status(of opponent: NearbyLobby.Opponent) -> String {
        if opponent.isReady { return "Ready" }
        if !opponent.isConnected { return "Connecting…" }
        return lobby.isCreator && !lobby.iAmReady ? "Wants to play" : "Connected"
    }

    /// A player on the Ready screen, in their side's colour (gold South, red North on both phones).
    private func playerTile(name: String, side: Player, status: String, ready: Bool, isMe: Bool) -> some View {
        let colour = side == .south ? Theme.gold : Theme.kenteRed
        return HStack(spacing: 14) {
            Circle()
                .fill(colour)
                .frame(width: 34, height: 34)
                .overlay(Text(String(name.prefix(1))).font(Theme.body(17)).foregroundStyle(Theme.night))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Theme.body(20))
                Text(isMe ? "You · \(status)" : status)
                    .font(Theme.caption(14))
                    .foregroundStyle(Theme.ivoryDim)
            }
            Spacer()
            Image(systemName: ready ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 26))
                .foregroundStyle(ready ? Theme.kenteGreen : Theme.ivoryDim.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Theme.ember, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(colour.opacity(0.6)))
    }

    // MARK: Pieces

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption())
            .foregroundStyle(Theme.ivoryDim)
    }

    private func row(_ title: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack {
            Text(title).font(Theme.body(18))
            Spacer()
            control()
        }
        .frame(minHeight: 44)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.ivoryDim)
            Spacer()
            Text(value)
        }
        .font(Theme.body(17))
    }

    private func helpLink(_ text: String) -> some View {
        Button(text) { showHelp = true }
            .font(Theme.caption(15))
            .frame(minHeight: 44)
            .accessibilityIdentifier("btn-nearby-help")
    }

    private func back() {
        if lobby.phase != .playing { lobby.cancel() }
        goBack()
    }

    // MARK: Local Network

    private var localNetworkOff: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lelu Oware can't look for phones nearby: Local Network is off for it.")
                .foregroundStyle(Theme.gold)
            Text("Turn it on in Settings ▸ Privacy & Security ▸ Local Network, then come back.")
                .font(Theme.caption(14))
                .foregroundStyle(Theme.ivoryDim)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("btn-open-settings")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .background(Theme.ember, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearby-local-network-off")
    }
}

/// A spinner while waiting on the other phone. Test launches show it still: a spinning view keeps
/// the app from settling, and XCUITest waits for that before every step.
struct WaitingMark: View {
    var body: some View {
        if LaunchOptions.fastAnimations {
            Image(systemName: "hourglass")
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
        } else {
            ProgressView().tint(Theme.gold)
        }
    }
}

/// How nearby play works: three steps, and what to check when the phones can't find each other.
private struct NearbyHelp: View {
    @State private var showTrouble = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("How nearby play works")
                    .font(Theme.title(28))
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(Theme.body(20))
                            .foregroundStyle(Theme.gold)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(Theme.body(19))
                            Text(step.detail)
                                .font(Theme.caption(15))
                                .foregroundStyle(Theme.ivoryDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button("Having trouble connecting?") { withAnimation { showTrouble.toggle() } }
                    .font(Theme.body(17))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("btn-trouble-connecting")
                if showTrouble {
                    ForEach(Self.trouble, id: \.self) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.gold).frame(width: 5, height: 5).accessibilityHidden(true)
                            Text(tip)
                                .font(Theme.caption(15))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Theme.body(17))
        .foregroundStyle(Theme.ivory)
        .tint(Theme.gold)
        .accessibilityIdentifier("nearby-help")
    }

    static let steps: [(title: String, detail: String)] = [
        ("Keep both phones close", "No internet is needed."),
        ("Start on one phone", "Tap Start nearby game."),
        ("Join on the other", "Choose the game when it appears."),
    ]

    static let trouble = [
        "Both phones need Lelu Oware open on Play nearby, with Wi-Fi switched on. They don't need to join a Wi-Fi network.",
        "If iPhone asked to find devices on your local network and you said no, turn Local Network on for Lelu Oware in Settings ▸ Privacy & Security ▸ Local Network.",
        "Stay within a few metres of each other, in the same room.",
        "Still nothing? Close Play nearby on both phones and open it again.",
    ]
}
