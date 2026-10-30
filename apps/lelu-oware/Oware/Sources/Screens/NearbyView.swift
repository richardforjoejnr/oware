import SwiftUI
import UIKit
import MatchKitNearby
import OwareEngine

/// Play nearby: host a game or join one on a phone close by (docs/NEARBY_PLAY.md). The game
/// itself is the usual game screen; this is everything before it starts.
struct NearbyView: View {
    @Environment(NearbyLobby.self) private var lobby
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    /// The demo player, Ama, instead of real phones.
    let demo: Bool
    let goBack: () -> Void

    @State private var starter: NearbyLobby.Starter = .creatorStarts
    /// Waiting for a name before hosting or joining.
    @State private var askingName: PendingStep?
    @State private var name = ""
    @State private var showHelp = false

    private enum PendingStep: Equatable { case host, join }

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
                    Text("Play nearby")
                        .font(Theme.title(34))
                        .foregroundStyle(Theme.ivory)
                        .accessibilityIdentifier("nearby-title")
                    if demo {
                        Text("Demo: \(DemoPlayer.name) plays on a pretend phone inside this one, the way a friend's phone would join.")
                            .font(Theme.caption(14))
                            .foregroundStyle(Theme.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if lobby.status == .localNetworkDenied {
                        localNetworkOff
                    }
                    if let step = askingName {
                        namePrompt(then: step)
                    } else {
                        content
                    }
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
        .onAppear { lobby.prepare(demo: demo) }
        .sheet(isPresented: $showHelp) {
            NearbyHelp()
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.ember)
        }
    }

    @ViewBuilder private var content: some View {
        switch lobby.phase {
        case .choosing, .playing:
            choosing
        case .hosting:
            waitingRoom
        case .browsing:
            gamesNearby
        case let .asking(game):
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    WaitingMark()
                    Text("Asking to join \(game)…")
                        .accessibilityIdentifier("nearby-asking")
                }
                QuietButton(title: "Cancel") { lobby.cancel() }
                    .accessibilityIdentifier("btn-cancel")
            }
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

    // MARK: Host or join

    private var choosing: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Two phones, one game, side by side. No Wi-Fi network or internet needed: just keep Wi-Fi and Bluetooth switched on.")
                .font(Theme.caption(15))
                .foregroundStyle(Theme.ivoryDim)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                QuietButton(title: "Host a game", subtitle: "\(NearbyLobby.rulesName(settings.rules)) rules", prominent: true) { start(.host) }
                    .accessibilityIdentifier("btn-host")
                Text("Who starts")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.ivoryDim)
                Picker("Who starts", selection: $starter) {
                    ForEach(NearbyLobby.Starter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("nearby-starter")
            }
            QuietButton(title: "Join a game", subtitle: "on a phone near you") { start(.join) }
                .accessibilityIdentifier("btn-join")
            Button("Can't find each other?") { showHelp = true }
                .font(Theme.caption(15))
                .frame(minHeight: 44)
                .accessibilityIdentifier("btn-nearby-help")
        }
    }

    private var waitingRoom: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                WaitingMark()
                Text("Waiting for a player…")
                    .accessibilityIdentifier("nearby-waiting")
            }
            Text("\(NearbyLobby.savedName() ?? "Your")'s game · \(NearbyLobby.rulesName(settings.rules)) · \(starterNote)")
                .font(Theme.caption(14))
                .foregroundStyle(Theme.ivoryDim)
            ForEach(lobby.joinRequests, id: \.peer) { request in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(request.name) wants to play")
                        .font(Theme.body(20))
                    HStack(spacing: 28) {
                        Button("Play") { Task { await lobby.accept(request) } }
                            .foregroundStyle(Theme.gold)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("btn-accept")
                            .accessibilityLabel("Play with \(request.name)")
                        Button("Not now") { Task { await lobby.decline(request) } }
                            .foregroundStyle(Theme.ivoryDim)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("btn-decline")
                    }
                    .font(Theme.body(18))
                    .buttonStyle(.plain)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.ember, in: RoundedRectangle(cornerRadius: 14))
            }
            QuietButton(title: "Stop hosting") { lobby.cancel() }
                .accessibilityIdentifier("btn-cancel")
        }
        .animation(.easeInOut(duration: 0.25), value: lobby.joinRequests)
    }

    private var starterNote: String {
        switch starter {
        case .creatorStarts: "you start"
        case .joiningPlayerStarts: "the other player starts"
        case .random: "random start"
        }
    }

    private var gamesNearby: some View {
        VStack(alignment: .leading, spacing: 12) {
            if lobby.games.isEmpty {
                HStack(spacing: 12) {
                    WaitingMark()
                    Text("Looking for games nearby…")
                        .accessibilityIdentifier("nearby-looking")
                }
                Text("Ask your friend to tap Host a game on their phone.")
                    .font(Theme.caption(14))
                    .foregroundStyle(Theme.ivoryDim)
            } else {
                Text("Games nearby")
                    .font(Theme.caption())
                    .foregroundStyle(Theme.ivoryDim)
                ForEach(lobby.games) { game in
                    QuietButton(title: game.name, subtitle: game.rules, prominent: true) {
                        lobby.join(game, name: NearbyLobby.savedName() ?? "", pace: settings.effectiveSpeed)
                    }
                        .accessibilityIdentifier("nearby-game-\(game.name)")
                }
            }
            QuietButton(title: "Back") { lobby.cancel() }
                .accessibilityIdentifier("btn-cancel")
        }
    }

    // MARK: Your name

    private func namePrompt(then step: PendingStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What should nearby players call you?")
                .font(Theme.body(20))
            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.done)
                .onSubmit { finishName(step) }
                .padding(12)
                .background(Theme.ember, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("nearby-name-field")
            Text("Only the phone you play with sees it. You can change it in Settings.")
                .font(Theme.caption(13))
                .foregroundStyle(Theme.ivoryDim)
            HStack(spacing: 28) {
                Button("Done") { finishName(step) }
                    .foregroundStyle(Theme.gold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("btn-name-done")
                Button("Cancel") { askingName = nil }
                    .foregroundStyle(Theme.ivoryDim)
            }
            .font(Theme.body(18))
            .frame(minHeight: 44)
            .buttonStyle(.plain)
        }
    }

    private func start(_ step: PendingStep) {
        guard let saved = NearbyLobby.savedName() else {
            name = ""
            askingName = step
            return
        }
        switch step {
        case .host: lobby.host(name: saved, rules: settings.rules, starter: starter, pace: settings.effectiveSpeed)
        case .join: lobby.browse()
        }
    }

    private func finishName(_ step: PendingStep) {
        NearbyLobby.saveName(name)
        guard NearbyLobby.savedName() != nil else { return }
        askingName = nil
        start(step)
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

/// "Can't find each other?": what nearby play needs, in plain words.
private struct NearbyHelp: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Finding each other")
                    .font(Theme.title(28))
                ForEach(Self.tips, id: \.self) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.gold).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(tip).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Theme.body(17))
        .foregroundStyle(Theme.ivory)
        .accessibilityIdentifier("nearby-help")
    }

    static let tips = [
        "Both phones need Lelu Oware, with Wi-Fi and Bluetooth switched on. They don't need to join a Wi-Fi network, and no internet is used.",
        "Stay within a few metres of each other, in the same room.",
        "If iPhone asked to find devices on your local network and you said no, turn Local Network on for Lelu Oware in Settings ▸ Privacy & Security.",
        "One of you taps Host a game; the other taps Join a game and picks it from the list.",
        "If a phone drops out mid-game, the game waits for it. After a minute you can finish against the computer instead.",
    ]
}
