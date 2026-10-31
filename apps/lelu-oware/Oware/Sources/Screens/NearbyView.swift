import SwiftUI
import UIKit
import MatchKitNearby
import OwareEngine

/// Play nearby (NEARBY_PLAY_REDESIGN.md §2): one screen. Look for games lists the games nearby, or
/// Start nearby game makes yours (and you move first); then Ready to play on both phones. The game
/// itself is the usual game screen. Never "host", "join mode" or "client" in the player's words.
///
/// Buttons follow Apple's guidance: every control has a shape, one filled (gold) button per screen
/// for the main action, bordered wood ones for the rest, links with an icon; plain text never looks
/// tappable.
struct NearbyView: View {
    @Environment(NearbyLobby.self) private var lobby
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// The demo player, Ama, instead of real phones.
    let demo: Bool
    let goBack: () -> Void

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
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(Theme.title(34))
                            .foregroundStyle(Theme.ivory)
                            .accessibilityIdentifier("nearby-title")
                            .accessibilityAddTraits(.isHeader)
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
                            .foregroundStyle(Theme.ivoryDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if lobby.phase == .lobby {
                        switch lobby.blocker {
                        case .localNetwork: localNetworkOff
                        case .wifi: wifiOff
                        case nil: EmptyView()
                        }
                    }
                    content
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.night.ignoresSafeArea())
        .font(Theme.body())
        .foregroundStyle(Theme.ivory)
        .tint(Theme.gold)
        .onDisappear { lobby.close() }
        // Back from Settings or Control Center: Wi-Fi or Local Network may have changed.
        .onChange(of: scenePhase) { _, phase in if phase == .active { lobby.recheck() } }
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
            VStack(alignment: .leading, spacing: 16) {
                Text(reason)
                    .accessibilityIdentifier("nearby-refused")
                Button("Back") { lobby.cancel() }
                    .buttonStyle(NearbyButtonStyle(.secondary))
                    .accessibilityIdentifier("btn-cancel")
            }
        }
    }

    // MARK: A. Start nearby game, games nearby

    private var startGame: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Start a game")
            row("Rules") {
                Menu {
                    Picker("Rules", selection: Binding(get: { rules.variant }, set: { variant = $0 })) {
                        Text("Abapa").tag(RuleSet.Variant.abapa)
                        Text("Nam-Nam").tag(RuleSet.Variant.namNam)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(NearbyLobby.rulesName(rules))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .font(Theme.body(17))
                    .foregroundStyle(Theme.ivory)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(Theme.wood, in: Capsule())
                    .overlay(Capsule().stroke(Theme.gold.opacity(0.55)))
                }
                .accessibilityLabel("Rules, \(NearbyLobby.rulesName(rules))")
                .accessibilityIdentifier("nearby-rules")
            }
            row("Your name") {
                HStack(spacing: 8) {
                    TextField(NearbyLobby.myName(saved: nil, gameCenter: GameCenter.shared.playerName), text: $name)
                        .multilineTextAlignment(.trailing)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .onChange(of: name) { _, name in NearbyLobby.saveName(name) }
                        .accessibilityLabel("Your name")
                        .accessibilityIdentifier("nearby-name-field")
                    Image(systemName: "pencil").foregroundStyle(Theme.ivoryDim).accessibilityHidden(true)
                }
                .font(Theme.body(17))
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .frame(maxWidth: 210)
                .background(Theme.night.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ivoryDim.opacity(0.35)))
            }
            Text("You move first. Your name is shown only to players near you.")
                .font(Theme.caption(13))
                .foregroundStyle(Theme.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)
            Button("Start nearby game") {
                lobby.start(name: NearbyLobby.myName, rules: rules, pace: settings.effectiveSpeed)
            }
            .buttonStyle(NearbyButtonStyle(.primary))
            .disabled(!lobby.canSearch)
            .accessibilityIdentifier("btn-start-nearby")
        }
        .padding(16)
        .background(Theme.ember, in: RoundedRectangle(cornerRadius: 16))
    }

    private var gamesNearby: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Join a friend's game")
            if !lobby.isLooking {
                Button { lobby.look() } label: {
                    Label("Look for games", systemImage: "magnifyingglass")
                }
                .buttonStyle(NearbyButtonStyle(.secondary))
                .disabled(!lobby.canSearch)
                .accessibilityIdentifier("btn-look-nearby")
            } else {
                HStack(spacing: 12) {
                    WaitingMark()
                    Text(lobby.games.isEmpty ? "Looking for games nearby…" : "Games nearby")
                        .font(Theme.body(17))
                        .accessibilityIdentifier("nearby-looking")
                    Spacer()
                    Button("Stop") { lobby.stopLooking() }
                        .buttonStyle(NearbyButtonStyle(.small))
                        .accessibilityLabel("Stop looking")
                        .accessibilityIdentifier("btn-stop-looking")
                }
                if lobby.games.isEmpty {
                    Text("Ask your friend to tap Start nearby game on their phone.")
                        .font(Theme.caption(14))
                        .foregroundStyle(Theme.ivoryDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lobby.games) { game in
                    gameCard(game)
                }
            }
        }
    }

    /// C. A game found nearby: "Ama's game", "Abapa · Ama starts", and a Join button.
    private func gameCard(_ game: NearbyListing) -> some View {
        let note = [game.rules, game.creatorStarts.map { NearbyLobby.startNote(creatorStarts: $0, creatorName: game.creatorName) }]
            .compactMap { $0 }.joined(separator: " · ")
        return Button {
            lobby.join(game, name: NearbyLobby.myName, pace: settings.effectiveSpeed)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name).font(Theme.body(20)).foregroundStyle(Theme.ivory)
                    if !note.isEmpty {
                        Text(note)
                            .font(Theme.caption(14))
                            .foregroundStyle(Theme.ivoryDim)
                    }
                }
                Spacer()
                Text("Join")
                    .font(Theme.body(17))
                    .foregroundStyle(Theme.night)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Theme.gold, in: Capsule())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.wood, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.45)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressedStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.joinLabel(name: game.name, note: note))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("nearby-game-\(game.name)")
    }

    /// "Join Ama's game, Abapa · Ama starts", or just "Join Ama's game".
    static func joinLabel(name: String, note: String) -> String {
        note.isEmpty ? "Join \(name)" : "Join \(name), \(note)"
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
                detail("Who starts", "You")
                detail("Your name", NearbyLobby.myName)
            }
            .padding(16)
            .background(Theme.ember, in: RoundedRectangle(cornerRadius: 16))
            Button("Cancel", role: .cancel) { lobby.cancel() }
                .buttonStyle(NearbyButtonStyle(.secondary))
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
            Button("Ready") { Task { await lobby.ready() } }
                .buttonStyle(NearbyButtonStyle(.primary))
                .disabled(!lobby.canPressReady)
                .accessibilityIdentifier("btn-ready")
            HStack(spacing: 12) {
                if lobby.canSayNotNow, let opponent = lobby.opponent {
                    Button("Not now") { Task { await lobby.notNow() } }
                        .buttonStyle(NearbyButtonStyle(.secondary))
                        .accessibilityIdentifier("btn-not-now")
                        .accessibilityLabel("Not now, \(opponent.name)")
                }
                Button("Cancel", role: .cancel) { lobby.cancel() }
                    .buttonStyle(NearbyButtonStyle(.secondary))
                    .accessibilityIdentifier("btn-cancel")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lobby.opponent)
    }

    private func status(of opponent: NearbyLobby.Opponent) -> String {
        if opponent.isReady { return "Ready" }
        if !opponent.isConnected { return "Connecting…" }
        return lobby.isCreator && !lobby.iAmReady ? "Wants to play" : "Connected"
    }

    /// A player on the Ready screen, in their side's colour (gold South, red North on both phones).
    /// Not a control: no border that could pass for a button.
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
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14)
                .fill(colour)
                .frame(width: 5)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.tileLabel(name: name, side: side, status: status, isMe: isMe))
        .accessibilityIdentifier(isMe ? "nearby-player-me" : "nearby-player-other")
    }

    /// The tile read as one: who, which side (said, not only shown in colour), and where they are.
    static func tileLabel(name: String, side: Player, status: String, isMe: Bool) -> String {
        "\(isMe ? "You, " : "")\(name), \(side == .south ? "gold" : "red") side, \(status)"
    }

    // MARK: Pieces

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.caption(13))
            .tracking(1.2)
            .foregroundStyle(Theme.ivoryDim)
            .accessibilityAddTraits(.isHeader)
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
        link(text, icon: "questionmark.circle") { showHelp = true }
            .accessibilityIdentifier("btn-nearby-help")
    }

    /// A minor action: gold, with an icon, so it reads as tappable without competing with buttons.
    private func link(_ text: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(Theme.body(16))
                .foregroundStyle(Theme.gold)
                .frame(minHeight: 44)
        }
        .buttonStyle(PressedStyle())
    }

    private func back() {
        if lobby.phase != .playing { lobby.cancel() }
        goBack()
    }

    // MARK: Local Network and Wi-Fi

    private var wifiOff: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wi-Fi seems to be off.")
            // No Open Settings: apps can only open their own page there, which has no Wi-Fi switch.
            Text("Nearby play needs Wi-Fi switched on, on both phones. You don't need to join a network. Turn it on in Control Center or Settings ▸ Wi-Fi, then come back.")
                .font(Theme.caption(14))
                .foregroundStyle(Theme.ivoryDim)
            if lobby.stillOff {
                Text("Still looks off.")
                    .font(Theme.caption(14))
                    .foregroundStyle(Theme.gold)
                    .accessibilityIdentifier("nearby-wifi-still-off")
            }
            HStack(spacing: 12) {
                Button("Check again") { lobby.checkAgain() }
                    .buttonStyle(NearbyButtonStyle(.small))
                    .accessibilityIdentifier("btn-check-wifi")
                Button("Try anyway") { lobby.tryAnyway() }
                    .buttonStyle(NearbyButtonStyle(.small))
                    .accessibilityIdentifier("btn-try-anyway")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .background(Theme.ember, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearby-wifi-off")
    }

    private var localNetworkOff: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lelu Oware can't look for phones nearby: Local Network is off for it.")
            Text("Turn it on in Settings ▸ Privacy & Security ▸ Local Network, then come back.")
                .font(Theme.caption(14))
                .foregroundStyle(Theme.ivoryDim)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(NearbyButtonStyle(.small))
            .accessibilityIdentifier("btn-open-settings")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .background(Theme.ember, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearby-local-network-off")
    }
}

/// Nearby play's buttons. Primary: filled gold, one per screen, the main action. Secondary: wood
/// with a gold edge. Small: a compact secondary for a row (Stop). All at least 44 pt tall.
struct NearbyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, small }
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    init(_ kind: Kind) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: kind == .small ? 10 : 14)
        return configuration.label
            .font(Theme.body(kind == .small ? 16 : 20))
            .foregroundStyle(kind == .primary ? Theme.night : Theme.ivory)
            .padding(.horizontal, kind == .small ? 14 : 18)
            .frame(maxWidth: kind == .small ? nil : .infinity, minHeight: kind == .small ? 44 : 52)
            .background {
                if kind == .primary {
                    shape.fill(LinearGradient(colors: [Theme.goldLight, Theme.gold, Theme.amber], startPoint: .top, endPoint: .bottom))
                } else {
                    shape.fill(Theme.wood)
                }
            }
            .overlay(shape.stroke(kind == .primary ? Theme.amber : Theme.gold.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.35), radius: 3, y: 2)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// No chrome of its own, just a dip when pressed (cards and links that draw their own shape).
private struct PressedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
    @Environment(\.dismiss) private var dismiss
    @State private var showTrouble = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("How nearby play works")
                        .font(Theme.title(28))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    // A visible way out (HIG, Sheets), not only the swipe down.
                    Button("Done") { dismiss() }
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.gold)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("btn-help-done")
                }
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
                Button { withAnimation { showTrouble.toggle() } } label: {
                    Label("Having trouble connecting?", systemImage: showTrouble ? "chevron.down" : "chevron.right")
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.gold)
                        .frame(minHeight: 44)
                }
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
        ("Join on the other", "Tap Look for games, then Join."),
    ]

    static let trouble = [
        "Both phones need Lelu Oware open on Play nearby, with Wi-Fi switched on. They don't need to join a Wi-Fi network.",
        "If iPhone asked to find devices on your local network and you said no, turn Local Network on for Lelu Oware in Settings ▸ Privacy & Security ▸ Local Network.",
        "Stay within a few metres of each other, in the same room.",
        "Still nothing? Close Play nearby on both phones and open it again.",
    ]
}
