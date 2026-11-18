import SwiftUI
import OwareAI

enum Screen: Hashable {
    case home
    case game
    case puzzles
    case heritage
    case journey
    case nearby
    case online
}

struct RootView: View {
    @Environment(GameSession.self) private var session
    @Environment(JourneyProgress.self) private var progress
    @Environment(AppSettings.self) private var settings
    @Environment(PuzzleLibrary.self) private var library
    @Environment(RiddleReminder.self) private var reminder
    @Environment(NearbyLobby.self) private var lobby
    @Environment(OnlinePlay.self) private var online
    @Environment(Invitations.self) private var invitations
    @Environment(OnlineHealth.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    /// Nearby with the demo player (Settings ▸ Try nearby play) rather than real phones.
    @State private var nearbyDemo = false
    @State private var screen: Screen = .home
    @State private var showSettings = false
    /// An invitation followed in the middle of a game with someone: joined once the player agrees.
    @State private var invitationToConfirm: URL?
    /// The carved-map opening; skipped for test launches so suites are not slowed.
    @State private var showSplash = RootView.splashThisLaunch != nil
    /// Decided once per launch (a static is created once), and never in test launches, which skip the splash.
    private static let splashThisLaunch: Duration? =
        !LaunchOptions.fastAnimations && !LaunchOptions.startGame && LaunchOptions.startScreen == nil
            ? SplashSchedule.durationForThisLaunch() : nil

    /// Nearby starts afresh here, as it is opened, not when its screen appears: an appearing view
    /// can run after the first tap (a quick Join) and undo it.
    private func openNearby(demo: Bool) {
        nearbyDemo = demo
        lobby.prepare(demo: demo || LaunchOptions.nearbyDemo)
        screen = .nearby
    }

    /// Straight to Ready to play in the game the link is for. Ignored while Play online is hidden.
    private func openInvitation(_ url: URL, leaving: Bool = false) {
        guard settings.showsOnlinePlay else { return }
        // The game saved on this phone: the same as Rejoin on Home, where it says how it goes.
        if online.rejoins(link: url) {
            online.rejoin(pace: settings.effectiveSpeed)
            showSettings = false
            showSplash = false
            screen = .home
            return
        }
        // In a game with someone who is there: ask before walking out of it.
        if !leaving, online.interrupts(link: url) {
            showSettings = false
            invitationToConfirm = url
            return
        }
        guard online.open(link: url, name: NearbyLobby.myName, pace: settings.effectiveSpeed, leaving: leaving) else { return }
        showSettings = false
        showSplash = false
        screen = .online
    }

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            if showSplash {
                SplashView(duration: RootView.splashThisLaunch ?? SplashSchedule.short) { withAnimation(.easeInOut(duration: 0.6)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
            switch screen {
            case .home:
                HomeView(startGame: { screen = .game },
                         openPuzzles: { screen = .puzzles },
                         openHeritage: { screen = .heritage },
                         openJourney: { screen = .journey },
                         openNearby: { openNearby(demo: false) },
                         openOnline: {
                             online.lobby.prepare(demo: false)
                             screen = .online
                         },
                         openSettings: { showSettings = true })
                    .transition(.opacity)
            case .game:
                GameView(goHome: { screen = .home },
                         goToPuzzles: { screen = .puzzles },
                         goToJourney: { screen = .journey })
                    .transition(.opacity)
            case .journey:
                JourneyView(goBack: { screen = .home }, startMatch: { chapter, opponent in
                    session.newGame(.journey(chapter: chapter, opponent: opponent), rules: settings.rules)
                    screen = .game
                })
                .transition(.opacity)
            case .nearby:
                NearbyView(demo: nearbyDemo || LaunchOptions.nearbyDemo, goBack: { screen = .home })
                    .transition(.opacity)
            case .online:
                // The same screen and lobby as nearby play, with a code in place of games nearby.
                NearbyView(demo: online.lobby.isDemo, goBack: { screen = .home })
                    .environment(online.lobby)
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
        .confirmationDialog("Leave this game to join the other one?",
                            isPresented: Binding(get: { invitationToConfirm != nil }, set: { if !$0 { invitationToConfirm = nil } }),
                            titleVisibility: .visible) {
            Button("Leave and join", role: .destructive) {
                if let link = invitationToConfirm { openInvitation(link, leaving: true) }
                invitationToConfirm = nil
            }
            Button("Keep playing", role: .cancel) { invitationToConfirm = nil }
        } message: {
            Text("\(session.opponentName) will see that you have left. This game can't be picked up again later.")
        }
        .statusBarHidden(true)
        // Text grows with the reader's setting, up to a size the layouts still hold.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        // Riddles follow the rules chosen in Settings.
        .onChange(of: settings.variant) { library.variant = settings.rules.variant }
        // The reminder is rescheduled each time the app comes forward, so it skips a day already done.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if settings.showsOnlinePlay { Task { await health.check() } }
            Task { await reminder.reschedule(solvedToday: library.dailySolved, streak: library.currentStreak()) }
        }
        // An invitation to an online game: tapped in a message (a universal link), or the join
        // page's "Open in Lelu Oware" button (leluoware://join?c=…).
        .onOpenURL { openInvitation($0) }
        // An invitation to play again: its notification was tapped (also the one that opened the app).
        .onChange(of: invitations.tapped, initial: true) { _, link in
            guard let link else { return }
            invitations.tapped = nil
            openInvitation(link)
        }
        // The same invitation arriving while the app is open: asked here, not as a banner.
        .overlay(alignment: .top) {
            if settings.showsOnlinePlay, let invitation = invitations.incoming {
                InvitationBanner(name: invitation.name,
                                 join: { if let link = invitations.join() { openInvitation(link) } },
                                 notNow: { Task { await invitations.notNow() } })
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: invitations.incoming)
        // Each launch: with invitations on, Apple is asked for the phone's token again.
        // (A TestFlight build learns a moment after launch that it offers Play online.)
        .task(id: settings.showsOnlinePlay) {
            guard settings.showsOnlinePlay else { return }
            // Is online play there? Home greys it out when it is not.
            await health.check()
            await invitations.started()
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { openInvitation(url) }
        }
        // A TestFlight build learns what it is from the App Store, then offers Settings ▸ Play online.
        .task { settings.offersOnlineSwitch = AppSettings.offersOnlineSwitch(in: await AppChannel.current()) }
        .onAppear {
            lobby.onStart = { screen = .game }
            online.lobby.onStart = { screen = .game }
            library.variant = settings.rules.variant
            switch LaunchOptions.startScreen {
            case "journey": screen = .journey
            case "puzzles": screen = .puzzles
            case "heritage": screen = .heritage
            case "lesson":
                session.startTutorial(step: 0, variant: settings.rules.variant)
                screen = .game
            default: break
            }
            if LaunchOptions.startGame, screen == .home {
                session.newGame(.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south), rules: settings.rules)
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

/// "Ama wants to play", over whatever screen is showing, with Join and Not now.
struct InvitationBanner: View {
    let name: String
    let join: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(name) wants to play")
                .font(Theme.body(19))
                .foregroundStyle(Theme.ivory)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("invitation-title")
            HStack(spacing: 12) {
                Button("Join", action: join)
                    .buttonStyle(NearbyButtonStyle(.primary))
                    .accessibilityIdentifier("btn-invitation-join")
                Button("Not now", action: notNow)
                    .buttonStyle(NearbyButtonStyle(.secondary))
                    .accessibilityIdentifier("btn-invitation-not-now")
            }
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Theme.ember, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.gold.opacity(0.6)))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}
