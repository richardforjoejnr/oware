import MatchKit
import MatchKitOnline
import OwareEngine
import XCTest
@testable import Oware

/// Two phones playing online, each with its own lobby and session, through the relay in memory
/// (`LocalRelay`): the same `OnlineTransport`, room messages and relay messages as two real
/// phones through AWS (docs/ONLINE_PLAY.md §10, Testing).
@MainActor
final class OnlinePairTests: XCTestCase {
    private func until(_ what: @autoclosure () -> String, timeout: TimeInterval = 5, _ condition: () async -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > end { return XCTFail("timed out waiting: \(what())") }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 80_000_000) }

    /// A phone's Play online, through `relay`.
    private func phone(_ relay: LocalRelay, install: String) -> NearbyLobby {
        let network = OnlineNetwork(dial: relay.dial, install: install, retryDelays: [0.01, 0.01, 0.02])
        let lobby = OnlinePlay(session: TestSupport.session(), network: network).lobby
        lobby.onStart = {}
        return lobby
    }

    private struct Phones {
        let relay: LocalRelay
        let ama: NearbyLobby
        let kofi: NearbyLobby
    }

    /// Ama starts a game and Kofi joins with her code. Nobody has pressed Ready.
    private func phones(rules: RuleSet = .abapa) async -> Phones {
        let relay = LocalRelay()
        let ama = phone(relay, install: "ama"), kofi = phone(relay, install: "kofi")
        ama.start(name: "Ama", rules: rules)
        await until("Ama has a code") { ama.roomCode != nil }
        XCTAssertTrue(kofi.join(code: ama.roomCode ?? "", name: "Kofi"))
        await until("Ama sees Kofi") { ama.phase == .ready && ama.opponent?.name == "Kofi" }
        await until("Kofi is in") { kofi.opponent?.isConnected == true }
        return Phones(relay: relay, ama: ama, kofi: kofi)
    }

    private func playing() async -> Phones {
        let p = await phones()
        await p.kofi.ready()
        await p.ama.ready()
        await until("both playing") { p.ama.phase == .playing && p.kofi.phase == .playing }
        await until("both started") { p.ama.session.isStarted && p.kofi.session.isStarted }
        return p
    }

    private func houses(_ lobby: NearbyLobby) -> [Int]? { lobby.link?.table?.match.houses }

    // MARK: Getting together

    func testStartingAGameGivesACodeToShare() async {
        let relay = LocalRelay(codes: ["K7M2QD"])
        let ama = phone(relay, install: "ama")
        XCTAssertNil(ama.blocker, "online play does not need Wi-Fi or the Local Network permission")
        ama.start(name: "Ama", rules: .abapa)
        XCTAssertEqual(ama.phase, .waiting)
        XCTAssertNil(ama.roomCode, "not until the relay has made the room")
        await until("the code") { ama.roomCode == "K7M2QD" }
        XCTAssertEqual(OnlineConfig.joinLink("K7M2QD").absoluteString, "https://leluoware.com/lelu-oware/join?c=K7M2QD")
        ama.cancel()
        await until("the room closes when she cancels") { await !relay.hasRoom("K7M2QD") }
        XCTAssertNil(ama.roomCode)
    }

    func testAFriendJoinsWithTheCodeAndBothSeeWhoAndWhat() async {
        let p = await phones(rules: .namNam)
        XCTAssertEqual(p.kofi.phase, .ready)
        XCTAssertEqual(p.kofi.opponent?.name, "Ama", "her name arrives with the game, not with the code")
        XCTAssertEqual(p.kofi.gameNote, "Nam-Nam · Ama starts")
        XCTAssertEqual(p.ama.gameNote, "Nam-Nam · You start")
        XCTAssertTrue(p.ama.canSayNotNow)
        XCTAssertFalse(p.kofi.canSayNotNow)
    }

    func testTheCodeCanBeTypedInAnyCaseWithSpaces() async {
        let relay = LocalRelay(codes: ["K7M2QD"])
        let ama = phone(relay, install: "ama"), kofi = phone(relay, install: "kofi")
        ama.start(name: "Ama", rules: .abapa)
        await until("code") { ama.roomCode != nil }
        XCTAssertTrue(kofi.join(code: " k7m 2qd ", name: "Kofi"))
        await until("Ama sees Kofi") { ama.opponent?.name == "Kofi" }
    }

    func testBothPressReadyAndTheGameIsPlayedOnBothPhones() async {
        let p = await playing()
        XCTAssertEqual(p.ama.session.remoteGame?.via, .online)
        XCTAssertEqual(p.ama.session.remoteGame?.mySide, .south)
        XCTAssertEqual(p.kofi.session.remoteGame?.mySide, .north)
        XCTAssertEqual(p.kofi.session.remoteGame?.opponentName, "Ama")
        XCTAssertTrue(p.ama.session.humanToMove, "whoever starts the game moves first")

        await p.ama.link?.send(.play(house: 2))
        await until("Kofi sees her move") { houses(p.kofi) == [2] }
        await p.kofi.link?.send(.play(house: 9))
        await until("Ama sees his") { houses(p.ama) == [2, 9] }
        XCTAssertEqual(p.ama.link?.table?.stateHash, p.kofi.link?.table?.stateHash, "the same position on both phones")
    }

    // MARK: Which rules

    /// The owner's two phones were set to different rules, and a game started on the Abapa one
    /// looked broken to the Nam-Nam player: the sowing stopped and the turn passed. The game
    /// follows whoever starts it, and the Ready screen now says so on both phones.
    func testTheGameUsesItsCreatorsRulesAndBothPhonesAreTold() async {
        let p = await phones(rules: .abapa)
        XCTAssertEqual(p.ama.gameVariant, .abapa)
        XCTAssertEqual(p.kofi.gameVariant, .abapa, "the joining phone has the game's rules, not its own")
        XCTAssertTrue(NearbyLobby.rulesHint(.abapa).contains("sow once and your turn ends"))
        XCTAssertTrue(NearbyLobby.rulesHint(.namNam).contains("sow on"))
        XCTAssertEqual(NearbyLobby.rulesDiffer(game: .abapa, mine: .namNam, creator: "Ama", iAmCreator: false),
                       "Ama started this game with Abapa. Your own games use Nam-Nam.")
        XCTAssertEqual(NearbyLobby.rulesDiffer(game: .abapa, mine: .namNam, creator: nil, iAmCreator: true),
                       "You chose Abapa for this game. Your other games use Nam-Nam.")
        XCTAssertNil(NearbyLobby.rulesDiffer(game: .namNam, mine: .namNam, creator: "Ama", iAmCreator: false))
    }

    // MARK: Invitations

    /// One phone's Play online with its lobby, as the app holds it.
    private func play(_ relay: LocalRelay, install: String) -> OnlinePlay {
        let network = OnlineNetwork(dial: relay.dial, install: install, retryDelays: [0.01, 0.01, 0.02])
        let play = OnlinePlay(session: TestSupport.session(), network: network)
        play.lobby.onStart = {}
        return play
    }

    /// Kofi taps the link Ama sent: no code to type, straight to Ready to play in her game.
    func testTappingTheInvitationLinkJoinsTheGame() async {
        let relay = LocalRelay()
        let ama = phone(relay, install: "ama"), kofi = play(relay, install: "kofi")
        ama.start(name: "Ama", rules: .abapa)
        await until("a code") { ama.roomCode != nil }
        let link = OnlineConfig.joinLink(ama.roomCode ?? "")

        XCTAssertTrue(kofi.open(link: link, name: "Kofi"))
        XCTAssertEqual(kofi.lobby.phase, .ready)
        await until("Ama sees Kofi") { ama.opponent?.name == "Kofi" }
        await until("Kofi sees whose game it is") { kofi.lobby.opponent?.name == "Ama" }
    }

    func testTheJoinPagesButtonAndTheOlderLinkFormOpenTheGameToo() async {
        for form in ["leluoware://join?c=%@", "https://leluoware.com/lelu-oware/join/%@"] {
            let relay = LocalRelay()
            let ama = phone(relay, install: "ama"), kofi = play(relay, install: "kofi")
            ama.start(name: "Ama", rules: .abapa)
            await until("a code") { ama.roomCode != nil }
            let link = URL(string: String(format: form, ama.roomCode ?? ""))!
            XCTAssertTrue(kofi.open(link: link, name: "Kofi"), form)
            await until("Ama sees Kofi (\(form))") { ama.opponent?.name == "Kofi" }
        }
    }

    func testALinkThatIsNotAnInvitationDoesNothing() async {
        let relay = LocalRelay()
        let kofi = play(relay, install: "kofi")
        XCTAssertFalse(kofi.open(link: URL(string: "https://leluoware.com/lelu-oware/privacy")!, name: "Kofi"))
        XCTAssertFalse(kofi.open(link: URL(string: "https://leluoware.com/lelu-oware/join?c=nonsense")!, name: "Kofi"))
        XCTAssertEqual(kofi.lobby.phase, .lobby)
    }

    /// A link tapped in the middle of a game does not end that game.
    func testAnInvitationDoesNotInterruptAGameBeingPlayed() async {
        let relay = LocalRelay(codes: ["K7M2QD", "ABCDEF"])
        let ama = phone(relay, install: "ama"), kofi = play(relay, install: "kofi"), yaw = phone(relay, install: "yaw")
        ama.start(name: "Ama", rules: .abapa)
        await until("a code") { ama.roomCode != nil }
        XCTAssertTrue(kofi.open(link: OnlineConfig.joinLink(ama.roomCode ?? ""), name: "Kofi"))
        await until("Ama sees Kofi") { ama.opponent?.name == "Kofi" }
        await until("Kofi is in") { kofi.lobby.opponent?.isConnected == true }
        await kofi.lobby.ready()
        await ama.ready()
        await until("playing") { kofi.lobby.phase == .playing && kofi.lobby.session.isStarted }

        yaw.start(name: "Yaw", rules: .abapa)
        await until("another game") { yaw.roomCode != nil }
        XCTAssertFalse(kofi.open(link: OnlineConfig.joinLink(yaw.roomCode ?? ""), name: "Kofi"))
        XCTAssertEqual(kofi.lobby.phase, .playing)
        XCTAssertEqual(kofi.lobby.session.remoteGame?.opponentName, "Ama")
    }

    /// A pasted message or link works where a code is asked for.
    func testAPastedInvitationJoinsLikeACode() async {
        let relay = LocalRelay()
        let ama = phone(relay, install: "ama"), kofi = phone(relay, install: "kofi")
        ama.start(name: "Ama", rules: .abapa)
        await until("a code") { ama.roomCode != nil }
        let code = ama.roomCode ?? ""
        let message = OnlineConfig.invitation(code: code) + " " + OnlineConfig.joinLink(code).absoluteString
        XCTAssertTrue(kofi.join(code: message, name: "Kofi"))
        await until("Ama sees Kofi") { ama.opponent?.name == "Kofi" }
    }

    func testTheInvitationSaysTheCodeAndTheQRCodeHoldsTheLink() throws {
        XCTAssertTrue(OnlineConfig.invitation(code: "K7M2QD").contains("K7M2QD"))
        let link = OnlineConfig.joinLink("K7M2QD")
        XCTAssertEqual(RoomCode(link: link)?.text, "K7M2QD", "the link the app shares is one the app opens")
        let image = try XCTUnwrap(InvitationQR.image(for: link))
        XCTAssertGreaterThan(image.size.width, 100)
        // Read it back as a camera would.
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
        let found = detector.features(in: CIImage(image: image)!).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(found, [link.absoluteString])
    }

    // MARK: The switch in Settings

    func testSettingsOffersTheSwitchInXcodeAndTestFlightBuildsButNeverAnAppStoreOne() {
        XCTAssertTrue(AppSettings.offersOnlineSwitch(in: .development))
        XCTAssertTrue(AppSettings.offersOnlineSwitch(in: .sandbox))
        XCTAssertFalse(AppSettings.offersOnlineSwitch(in: .appStore))
    }

    func testPlayOnlineShowsOnlyWhenSwitchedOnInABuildThatOffersIt() {
        let defaults = TestSupport.defaults()
        let settings = AppSettings(defaults: defaults, testMode: true)
        XCTAssertFalse(settings.onlinePlayOn, "off until asked for")
        XCTAssertFalse(settings.showsOnlinePlay)
        settings.onlinePlayOn = true
        XCTAssertTrue(settings.showsOnlinePlay)
        XCTAssertTrue(AppSettings(defaults: defaults, testMode: true).onlinePlayOn, "remembered")

        // The same phone later gets the App Store build: the switch it had on no longer counts.
        settings.offersOnlineSwitch = false
        XCTAssertFalse(settings.showsOnlinePlay)
    }

    /// Each build knows its relay: dev for builds from Xcode (which is what runs these tests).
    func testTheBuildCarriesItsRelaysAddress() {
        XCTAssertEqual(OnlineConfig.relay.scheme, "wss")
        XCTAssertTrue(OnlineConfig.relay.absoluteString.hasSuffix("/dev"), OnlineConfig.relay.absoluteString)
        XCTAssertEqual(OnlineConfig.relay(from: "wss://example.com/prod").absoluteString, "wss://example.com/prod")
        XCTAssertEqual(OnlineConfig.relay(from: nil).host, "play.leluoware.com")
        XCTAssertEqual(OnlineConfig.relay(from: "$(RELAY_URL)").host, "play.leluoware.com", "a setting that was never filled in")
        XCTAssertEqual(OnlineConfig.relay(from: "").host, "play.leluoware.com")
    }

    /// `-onlinePlay YES` at launch turns on the switch in Settings, the same one the player has:
    /// so turning it off in Settings takes Play online off Home (the owner found it stayed).
    func testTheLaunchSwitchTurnsOnTheSettingsSwitchWhichCanTurnItOffAgain() {
        let defaults = TestSupport.defaults()
        defaults.set(true, forKey: "onlinePlay")   // what an earlier build left behind
        LaunchOptions.keepOnlineSwitches(["Oware", "-onlinePlay", "YES", "-relayURL", "ws://localhost:8787"], defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "onlinePlay"), "the old switch that Settings could not reach is gone")
        XCTAssertEqual(defaults.string(forKey: "relayURL"), "ws://localhost:8787")
        let settings = AppSettings(defaults: defaults, testMode: true)
        XCTAssertTrue(settings.onlinePlayOn)
        XCTAssertTrue(settings.showsOnlinePlay)

        settings.onlinePlayOn = false
        XCTAssertFalse(settings.showsOnlinePlay, "off in Settings is off on Home")
        LaunchOptions.keepOnlineSwitches(["Oware"], defaults: defaults)
        XCTAssertFalse(AppSettings(defaults: defaults, testMode: true).showsOnlinePlay, "and stays off on the next launch")
    }

    // MARK: Not getting in

    func testSomethingThatIsNotACodeIsNotSent() async {
        let relay = LocalRelay()
        let kofi = phone(relay, install: "kofi")
        XCTAssertFalse(kofi.join(code: "K7M2Q", name: "Kofi"))
        XCTAssertFalse(kofi.join(code: "K7M2Q0", name: "Kofi"), "0 is never in a code")
        XCTAssertEqual(kofi.phase, .lobby)
        await settle()
        let asked = await relay.received["join"]
        XCTAssertNil(asked)
    }

    func testAWrongCodeSaysSoAndGoesBack() async {
        let relay = LocalRelay()
        let kofi = phone(relay, install: "kofi")
        XCTAssertTrue(kofi.join(code: "ZZZZZZ", name: "Kofi"))
        await until("told") { kofi.phase == .refused(OnlineNetwork.explain(.notFound)) }
        XCTAssertNil(kofi.link)
        kofi.cancel()
        XCTAssertEqual(kofi.phase, .lobby)
    }

    func testAThirdPhoneFindsTheGameFull() async {
        let p = await phones()
        let yaw = phone(p.relay, install: "yaw")
        XCTAssertTrue(yaw.join(code: p.ama.roomCode ?? "", name: "Yaw"))
        await until("told") { yaw.phase == .refused(OnlineNetwork.explain(.full)) }
        XCTAssertEqual(p.ama.opponent?.name, "Kofi", "the game in progress is not disturbed")
    }

    func testWithNoInternetStartingAGameSaysSo() async {
        let relay = LocalRelay()
        await relay.setReachable(false)
        let ama = phone(relay, install: "ama")
        ama.start(name: "Ama", rules: .abapa)
        await until("told") { ama.phase == .refused(OnlineNetwork.unreachable) }
        XCTAssertNil(ama.roomCode)
    }

    func testWhenOnlinePlayIsRestingItSaysSo() async {
        let relay = LocalRelay()
        await relay.setPaused(true)
        let ama = phone(relay, install: "ama")
        ama.start(name: "Ama", rules: .abapa)
        await until("told") { ama.phase == .refused("Online play is resting. Try again later.") }
    }

    func testEveryRefusalHasWordsForThePlayer() {
        for reason in RelayEvent.Refusal.allCases {
            let words = OnlineNetwork.explain(reason)
            XCTAssertFalse(words.isEmpty)
            XCTAssertFalse(words.contains("relay") || words.contains("server") || words.contains("room"), words)
        }
    }

    // MARK: Before the game

    func testNotNowSendsTheFriendAwayAndKeepsTheCode() async {
        let p = await phones()
        let code = p.ama.roomCode
        await p.ama.notNow()
        await until("Kofi is told") { p.kofi.phase == .refused("They said not this time.") }
        XCTAssertEqual(p.ama.phase, .waiting)
        XCTAssertEqual(p.ama.roomCode, code, "the same code works for the next friend")
    }

    func testAFriendWhoLeavesBeforeTheGameIsNoLongerShown() async {
        let p = await phones()
        p.kofi.cancel()
        await until("Ama is waiting again") { p.ama.phase == .waiting && p.ama.opponent == nil }
    }

    // MARK: Connections that break

    /// Kofi's signal goes mid-game. His phone takes its seat back by itself, and Ama's move made
    /// while he was away is on his board when he is back.
    func testAConnectionThatBreaksMidGameComesBackToTheSameGame() async {
        let p = await playing()
        await p.ama.link?.send(.play(house: 2))
        await until("first move") { houses(p.kofi) == [2] }

        await p.relay.setReachable(false, cutting: true)
        await until("Ama sees Kofi reconnecting") { p.ama.session.isReconnecting }
        await until("Kofi sees it too") { p.kofi.session.isReconnecting }
        await p.kofi.link?.send(.play(house: 9))   // played with no signal
        await settle()
        XCTAssertEqual(houses(p.ama), [2], "nothing arrives while the link is down")

        await p.relay.setReachable(true)
        await until("his move arrives once both are back") { houses(p.ama) == [2, 9] }
        await until("and he sees it played") { houses(p.kofi) == [2, 9] }
        await until("nobody is reconnecting") { !p.ama.session.isReconnecting && !p.kofi.session.isReconnecting }
        let rejoins = await p.relay.received["rejoin"] ?? 0
        XCTAssertGreaterThanOrEqual(rejoins, 2, "each phone took its seat back with its token")
    }

    func testWhenTheOtherPlayerLeavesTheGameSaysSo() async {
        let p = await playing()
        await p.kofi.session.link?.leave()
        await until("Ama is told") { p.ama.session.opponentLeft }
    }

    // MARK: The rules, with seeds that take time to sow

    /// A board that takes a while over every move, as the real one does, and remembers what it
    /// was asked to show: each sowing in full (`animate`), or a position put down at once (`render`).
    @MainActor
    final class SlowBoard: BoardAnimator {
        var humanSide: Player?
        var sown: [[MoveEvent]] = []
        var putDown = 0
        var seconds: Double
        init(seconds: Double) { self.seconds = seconds }

        func animate(events: [MoveEvent], from before: GameState, to after: GameState) async {
            sown.append(events)
            try? await Task.sleep(for: .seconds(seconds))
        }

        func render(_ state: GameState) { putDown += 1 }
    }

    struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    /// A whole online game in each rule set, with sowing that takes longer than the messages do.
    /// Every move is sown in full on both phones, once, and leaves both boards where the same
    /// move leaves a board on one phone. In Nam-Nam that includes every relay lap: a last seed in
    /// a house with seeds is scooped up and sown on before the turn passes.
    func testEveryMoveOfAnOnlineGameIsSownInFullOnBothPhones() async throws {
        for rules in [RuleSet.namNam, .abapa] {
            let relay = LocalRelay()
            let ama = phone(relay, install: "ama"), kofi = phone(relay, install: "kofi")
            let amaBoard = SlowBoard(seconds: 0.03), kofiBoard = SlowBoard(seconds: 0.05)
            ama.session.attach(amaBoard)
            kofi.session.attach(kofiBoard)
            ama.start(name: "Ama", rules: rules)
            await until("a code") { ama.roomCode != nil }
            XCTAssertTrue(kofi.join(code: ama.roomCode ?? "", name: "Kofi"))
            await until("Kofi is in") { kofi.opponent?.isConnected == true && ama.opponent != nil }
            await kofi.ready()
            await ama.ready()
            await until("started") { ama.session.isStarted && kofi.session.isStarted }
            XCTAssertEqual(kofi.session.state.rules, rules, "the joining phone plays the rules of the game it joined")
            let putDownAtStart = (amaBoard.putDown, kofiBoard.putDown)
            amaBoard.sown = []
            kofiBoard.sown = []

            var alone = GameState.initial(rules: rules)
            var rng = LCG(s: 5)
            var plies = 0, relays = 0
            while !alone.isOver, plies < 60 {
                let mover = alone.sideToMove == .south ? ama.session : kofi.session
                await until("\(rules.variant) move \(plies + 1): the mover's turn", timeout: 10) { mover.humanToMove }
                XCTAssertEqual(mover.state, alone, "\(rules.variant) before move \(plies + 1)")
                let move = try XCTUnwrap(alone.legalMoves().randomElement(using: &rng))
                let result = try alone.applying(move)
                relays += result.events.filter { if case .relay = $0 { true } else { false } }.count
                alone = result.state
                mover.play(house: move.absoluteIndex)
                plies += 1
                await until("\(rules.variant) move \(plies) settles on both phones", timeout: 10) {
                    ama.session.state == alone && kofi.session.state == alone
                        && !ama.session.isAnimating && !kofi.session.isAnimating
                }
                XCTAssertEqual(amaBoard.sown.count, plies, "\(rules.variant): Ama's board sowed move \(plies) once")
                XCTAssertEqual(kofiBoard.sown.count, plies, "\(rules.variant): Kofi's board sowed move \(plies) once")
                XCTAssertEqual(amaBoard.sown.last, result.events, "\(rules.variant) move \(plies): the whole sowing, on Ama's board")
                XCTAssertEqual(kofiBoard.sown.last, result.events, "\(rules.variant) move \(plies): the whole sowing, on Kofi's board")
                // Nam-Nam ends a round by putting the next one down; nothing else may jump the board.
                let roundsEnded = alone.roundHistory.count
                XCTAssertLessThanOrEqual(amaBoard.putDown - putDownAtStart.0, roundsEnded, "\(rules.variant) move \(plies): Ama's board jumped")
                XCTAssertLessThanOrEqual(kofiBoard.putDown - putDownAtStart.1, roundsEnded, "\(rules.variant) move \(plies): Kofi's board jumped")
            }
            if rules.variant == .namNam { XCTAssertGreaterThan(relays, 5, "the game had relay sowing in it") }
            ama.cancel()
            kofi.cancel()
        }
    }

    /// Through the real relay two messages sent close together can arrive the other way round.
    /// Nothing is lost by that: both sowing speeds are known (they go out with Ready, one after
    /// the other), and a whole game is still played the same on both phones.
    func testMessagesArrivingOutOfOrderLoseNothing() async throws {
        for round in 0..<6 {
            let relay = LocalRelay()
            await relay.setDisorder(true)
            let ama = phone(relay, install: "ama"), kofi = phone(relay, install: "kofi")
            ama.start(name: "Ama", rules: .namNam, pace: 1.0)
            await until("a code") { ama.roomCode != nil }
            XCTAssertTrue(kofi.join(code: ama.roomCode ?? "", name: "Kofi", pace: 0.7))
            await until("Kofi is in") { kofi.opponent?.isConnected == true && ama.opponent != nil }
            await kofi.ready()
            await ama.ready()
            await until("round \(round): started") { ama.session.isStarted && kofi.session.isStarted }
            await until("round \(round): both phones sow at the slower speed") {
                ama.session.sharedPace == 0.7 && kofi.session.sharedPace == 0.7
            }

            var alone = GameState.initial(rules: .namNam)
            var rng = LCG(s: UInt64(round + 1))
            var plies = 0
            while !alone.isOver, plies < 16 {
                let mover = alone.sideToMove == .south ? ama.session : kofi.session
                await until("round \(round) move \(plies + 1): the mover's turn") { mover.humanToMove }
                let move = try XCTUnwrap(alone.legalMoves().randomElement(using: &rng))
                alone = try alone.applying(move).state
                mover.play(house: move.absoluteIndex)
                // A ping goes out with the move, as the heartbeat's sometimes does.
                await (mover === ama.session ? ama : kofi).link?.tick()
                plies += 1
                await until("round \(round) move \(plies) on both phones") {
                    ama.session.state == alone && kofi.session.state == alone
                }
            }
            ama.cancel()
            kofi.cancel()
        }
    }

    // MARK: A real relay

    /// The same two phones through a real relay, when one is given:
    /// `TEST_RUNNER_RELAY_URL=ws://localhost:8787 xcodebuild test …` with `npm run dev` running in
    /// the AWS repo's apps/lelu-play, or a deployed stage's `wss://` address. Skipped otherwise.
    func testTwoPhonesPlayThroughARealRelay() async throws {
        guard let url = ProcessInfo.processInfo.environment["RELAY_URL"].flatMap(URL.init(string:)) else {
            throw XCTSkip("no RELAY_URL")
        }
        func phone() -> NearbyLobby {
            let network = OnlineNetwork(dial: OnlineTransport.dial(url), install: UUID().uuidString, retryDelays: [0.5, 1, 2])
            let lobby = OnlinePlay(session: TestSupport.session(), network: network).lobby
            lobby.onStart = {}
            return lobby
        }
        let ama = phone(), kofi = phone()
        ama.start(name: "Ama", rules: .abapa)
        await until("a code from the relay", timeout: 20) { ama.roomCode != nil }
        XCTAssertNotNil(RoomCode(ama.roomCode ?? ""), "a code a player can type: \(ama.roomCode ?? "none")")
        XCTAssertTrue(kofi.join(code: ama.roomCode ?? "", name: "Kofi"))
        await until("Ama sees Kofi", timeout: 20) { ama.opponent?.name == "Kofi" }
        await until("Kofi is in", timeout: 20) { kofi.opponent?.isConnected == true }
        await kofi.ready()
        await ama.ready()
        await until("both playing", timeout: 20) { ama.phase == .playing && kofi.phase == .playing }
        await ama.link?.send(.play(house: 2))
        await until("Kofi sees her move", timeout: 20) { houses(kofi) == [2] }

        // Kofi's connection breaks; his phone takes its seat back and the game goes on.
        (kofi.network as? OnlineNetwork)?.transport?.dropConnection()
        await until("Ama sees him reconnecting", timeout: 20) { ama.session.isReconnecting }
        await until("and back", timeout: 30) { !ama.session.isReconnecting && !kofi.session.isReconnecting }
        await kofi.link?.send(.play(house: 9))
        await until("his move after reconnecting", timeout: 20) { houses(ama) == [2, 9] }
        await kofi.session.link?.leave()
        await ama.session.link?.leave()
    }

    // MARK: The demo player

    /// `--online-demo`: Ama joins the game you start, through a relay inside the app.
    func testInTheDemoAmaJoinsReadiesAndPlays() async {
        let script = DemoPlayer.Script(thinkTime: 0.01, joinDelay: 0.01)
        let lobby = OnlinePlay(session: TestSupport.session(), network: .demo(script: script)).lobby
        lobby.onStart = {}
        XCTAssertTrue(lobby.isDemo)
        lobby.start(name: "Kofi", rules: .abapa)
        await until("a code") { lobby.roomCode != nil }
        await until("Ama comes") { lobby.opponent?.name == DemoPlayer.name }
        await until("and is ready") { lobby.opponent?.isReady == true }
        await lobby.ready()
        await until("the game starts") { lobby.phase == .playing && lobby.session.isStarted }
        await lobby.link?.send(.play(house: 2))
        await until("Ama answers") { (houses(lobby)?.count ?? 0) >= 2 }
        lobby.cancel()
    }
}
