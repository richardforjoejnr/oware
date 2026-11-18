import MatchKit
import MatchKitOnline
import OwareEngine
import XCTest
@testable import Oware

/// An online game survives the app being closed (docs/ONLINE_PLAY.md §5): each phone saves the
/// game after every snapshot, and opens it again from Home. Two phones through the relay in
/// memory; "closing the app" drops a phone's connection with no goodbye and throws its lobby and
/// session away, and "opening it" makes new ones over the same saved files and Keychain.
@MainActor
final class OnlineRejoinTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func until(_ what: @autoclosure () -> String, timeout: TimeInterval = 8, _ condition: () async -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > end { return XCTFail("timed out waiting: \(what())") }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func settle(_ seconds: Double = 0.08) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// The relays of this test. Phones hold their relay only loosely, as they do the real one, so
    /// the test keeps each for as long as it runs.
    private var relays: [LocalRelay] = []

    private func newRelay(codes: [String] = ["K7M2QD"]) -> LocalRelay {
        let relay = LocalRelay(codes: codes)
        relays.append(relay)
        return relay
    }

    /// One phone: what it keeps (a folder and a Keychain of its own) and the app running on it.
    @MainActor
    final class Phone {
        let folder: URL
        let secrets: MemorySecrets
        let install: String
        let dial: OnlineTransport.Dial
        let play: OnlinePlay
        let saves: OnlineSaves
        var lobby: NearbyLobby { play.lobby }
        var session: GameSession { play.lobby.session }
        var transport: OnlineTransport? { (play.lobby.network as? OnlineNetwork)?.transport }

        init(dial: @escaping OnlineTransport.Dial, install: String, folder: URL? = nil, secrets: MemorySecrets = MemorySecrets()) {
            self.folder = folder ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            self.secrets = secrets
            self.install = install
            self.dial = dial
            saves = OnlineSaves(directory: self.folder, secrets: secrets)
            play = OnlinePlay(session: TestSupport.session(),
                              network: OnlineNetwork(dial: dial, install: install, retryDelays: [0.01, 0.01, 0.02]), saves: saves)
            play.lobby.onStart = {}
        }

        /// The app is closed: no goodbye to anyone. What is on disk and in the Keychain stays.
        func closeApp() {
            transport?.abandon()
            session.link?.room.stop()
        }

        /// The app is opened again (through `dial`, or another relay).
        func openApp(dial: OnlineTransport.Dial? = nil) -> Phone {
            Phone(dial: dial ?? self.dial, install: install, folder: folder, secrets: secrets)
        }
    }

    /// Ama invites, Kofi joins with her code, both press Ready: the game is on.
    private func started(_ relay: LocalRelay, rules: RuleSet = .abapa) async -> (ama: Phone, kofi: Phone) {
        let ama = Phone(dial: relay.dial, install: "ama"), kofi = Phone(dial: relay.dial, install: "kofi")
        ama.lobby.start(name: "Ama", rules: rules)
        await until("Ama has a code") { ama.lobby.roomCode != nil }
        XCTAssertTrue(kofi.lobby.join(code: ama.lobby.roomCode ?? "", name: "Kofi"))
        await until("Kofi is in") { kofi.lobby.opponent?.isConnected == true && ama.lobby.opponent != nil }
        await kofi.lobby.ready()
        await ama.lobby.ready()
        await until("the game starts") {
            ama.lobby.phase == .playing && kofi.lobby.phase == .playing && ama.session.isStarted && kofi.session.isStarted
        }
        return (ama, kofi)
    }

    /// One move on `mover`'s phone, seen on both.
    private func play(_ house: Int, on mover: Phone, with other: Phone) async {
        let count = mover.session.state.moveNumber
        await until("it is their turn") { mover.session.humanToMove }
        mover.session.play(house: house)
        await until("move \(count + 1) on both phones: mover at \(mover.session.state.moveNumber), other at \(other.session.state.moveNumber), "
                    + "reconnecting \(mover.session.isReconnecting) \(other.session.isReconnecting), "
                    + "tables \(mover.session.link?.table?.match.houses ?? []) \(other.session.link?.table?.match.houses ?? [])") {
            mover.session.state.moveNumber == count + 1 && other.session.state == mover.session.state
        }
    }

    // MARK: - Saving

    func testNothingIsSavedBeforeTheGameStarts() async {
        let relay = newRelay()
        let ama = Phone(dial: relay.dial, install: "ama"), kofi = Phone(dial: relay.dial, install: "kofi")
        ama.lobby.start(name: "Ama", rules: .abapa)
        await until("a code") { ama.lobby.roomCode != nil }
        XCTAssertTrue(kofi.lobby.join(code: ama.lobby.roomCode ?? "", name: "Kofi"))
        await until("Kofi is in") { kofi.lobby.opponent?.isConnected == true }
        await settle()
        XCTAssertNil(ama.saves.current)
        XCTAssertNil(kofi.saves.current)
        XCTAssertNil(ama.play.saved)
    }

    func testEachPhoneSavesTheGameAfterEverySnapshot() async throws {
        let p = await started(newRelay(codes: ["K7M2QD"]))
        await until("both saved the opening") { p.ama.saves.current != nil && p.kofi.saves.current != nil }
        let hers = try XCTUnwrap(p.ama.saves.current), his = try XCTUnwrap(p.kofi.saves.current)
        XCTAssertEqual(hers.code, "K7M2QD")
        XCTAssertEqual(his.code, "K7M2QD")
        XCTAssertEqual(hers.seat, 0, "she made the game")
        XCTAssertEqual(his.seat, 1)
        XCTAssertEqual(hers.opponentName, "Kofi")
        XCTAssertEqual(his.opponentName, "Ama")
        XCTAssertEqual(hers.relay.token, p.ama.transport?.seat?.token)
        XCTAssertFalse(his.relay.token.isEmpty)
        XCTAssertNotEqual(hers.relay.token, his.relay.token)

        await play(2, on: p.ama, with: p.kofi)
        await until("saved with her move") { p.ama.saves.current?.table.match.houses == [2] && p.kofi.saves.current?.table.match.houses == [2] }
        await play(9, on: p.kofi, with: p.ama)
        await until("and his") { p.ama.saves.current?.table.match.houses == [2, 9] && p.kofi.saves.current?.table.match.houses == [2, 9] }

        // It is on disk and in the Keychain, not only in memory: another reader finds the same.
        XCTAssertEqual(OnlineSaves(directory: p.kofi.folder, secrets: p.kofi.secrets).current, p.kofi.saves.current)
    }

    func testTheTokensAreInTheKeychainAndNowhereElse() async throws {
        let p = await started(newRelay())
        await until("saved") { p.kofi.saves.current != nil && p.ama.saves.current != nil }
        for phone in [p.ama, p.kofi] {
            let save = try XCTUnwrap(phone.saves.current)
            let files = try FileManager.default.contentsOfDirectory(at: phone.folder, includingPropertiesForKeys: nil)
            XCTAssertFalse(files.isEmpty)
            for file in files {
                let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
                XCTAssertFalse(text.contains(save.relay.token), "the seat token is in \(file.lastPathComponent)")
                for token in save.room.tokens.values {
                    XCTAssertFalse(text.localizedCaseInsensitiveContains(token.uuidString), "a room token is in \(file.lastPathComponent)")
                }
            }
            let kept = String(decoding: try XCTUnwrap(phone.secrets.read(OnlineSaves.secretsKey)), as: UTF8.self)
            XCTAssertTrue(kept.contains(save.relay.token))
            // Without the Keychain there is no game to come back to: the file alone is not enough.
            XCTAssertNil(OnlineSaves(directory: phone.folder, secrets: MemorySecrets()).current)
        }
    }

    func testTheSaveIsRemovedWhenTheGameEndsAndARematchIsSavedAgain() async {
        let p = await started(newRelay())
        await until("saved") { p.ama.saves.current != nil && p.kofi.saves.current != nil }
        p.kofi.session.resign()
        await until("over on both") { p.ama.session.isGameOver && p.kofi.session.isGameOver }
        await until("nothing to come back to") { p.ama.saves.current == nil && p.kofi.saves.current == nil }
        XCTAssertNil(p.ama.secrets.read(OnlineSaves.secretsKey), "the tokens go with it")
        XCTAssertNil(OnlineSaves(directory: p.ama.folder, secrets: p.ama.secrets).current)

        p.ama.session.requestRematch()
        p.kofi.session.requestRematch()
        await until("the next game is saved") { p.ama.saves.current?.table.match.game == 2 && p.kofi.saves.current?.table.match.game == 2 }
    }

    func testTheSaveIsRemovedWhenAPlayerLeavesOnBothPhones() async {
        let p = await started(newRelay())
        await until("saved") { p.ama.saves.current != nil && p.kofi.saves.current != nil }
        p.kofi.session.leaveNearbyGame()
        XCTAssertNil(p.kofi.saves.current, "he left")
        await until("Ama is told he left") { p.ama.session.opponentLeft }
        XCTAssertNil(p.ama.saves.current, "nobody to carry on with")
    }

    func testTheSaveIsRemovedWhenThePlayerCarriesOnAgainstTheComputer() async {
        let p = await started(newRelay())
        await until("saved") { p.ama.saves.current != nil }
        p.kofi.session.leaveNearbyGame()
        await until("Ama may play the computer") { p.ama.session.offersComputer }
        p.ama.session.finishAgainstComputer(difficulty: .beginner)
        XCTAssertNil(p.ama.saves.current)
    }

    func testStartingAnotherKindOfGameKeepsTheSave() async throws {
        let p = await started(newRelay())
        await until("saved") { p.kofi.saves.current != nil }
        p.kofi.closeApp()
        let kofi = p.kofi.openApp()
        XCTAssertNotNil(kofi.play.saved)
        kofi.session.newGame(.passAndPlay, rules: .abapa)
        XCTAssertNotNil(kofi.play.saved, "the online game is still there to come back to")
    }

    // MARK: - Coming back

    func testOpeningTheAppFindsTheSavedGame() async throws {
        let p = await started(newRelay(codes: ["K7M2QD"]))
        await play(2, on: p.ama, with: p.kofi)
        await until("saved") { p.kofi.saves.current?.table.match.houses == [2] }
        p.kofi.closeApp()

        let kofi = p.kofi.openApp()
        let saved = try XCTUnwrap(kofi.play.saved, "Home has a game to offer")
        XCTAssertEqual(saved.opponentName, "Ama")
        XCTAssertEqual(saved.code, "K7M2QD")
        XCTAssertEqual(OnlinePlay.rejoinTitle(saved), "Your game with Ama")
        XCTAssertEqual(kofi.play.rejoining, .no)
        XCTAssertNil(kofi.session.link, "nothing is connected until Rejoin")
    }

    func testTheGuestClosesTheAppAndRejoinsTheSameGame() async throws {
        let relay = newRelay()
        let p = await started(relay)
        await play(2, on: p.ama, with: p.kofi)
        await until("saved") { p.kofi.saves.current?.table.match.houses == [2] }
        p.kofi.closeApp()
        await until("Ama sees him reconnecting") { p.ama.session.isReconnecting }
        XCTAssertFalse(p.ama.session.opponentLeft, "closing the app is not leaving")

        let kofi = p.kofi.openApp()
        var opened = false
        kofi.lobby.onStart = { opened = true }
        XCTAssertTrue(kofi.play.rejoin())
        await until("he is back in the game") { kofi.play.rejoining == .no && kofi.session.link != nil }
        XCTAssertTrue(opened, "the board opens")
        XCTAssertEqual(kofi.lobby.phase, .playing)
        XCTAssertEqual(kofi.session.remoteGame, RemoteGame(mySide: .north, opponentName: "Ama", via: .online))
        XCTAssertEqual(kofi.session.state, p.ama.session.state, "the board as it was")
        await until("both see each other") { !kofi.session.isReconnecting && !p.ama.session.isReconnecting }
        XCTAssertTrue(kofi.session.isStarted)
        let rejoins = await relay.received["rejoin"]
        XCTAssertEqual(rejoins, 1, "with his seat token, not as a new player")

        await play(9, on: kofi, with: p.ama)
        await play(3, on: p.ama, with: kofi)
        await until("and it is saved as it goes") { kofi.saves.current?.table.match.houses == [2, 9, 3] }
    }

    func testAMovePlayedWhileTheGuestWasAwayIsThereWhenHeRejoins() async throws {
        let p = await started(newRelay())
        await play(2, on: p.ama, with: p.kofi)
        await play(9, on: p.kofi, with: p.ama)
        await until("saved") { p.kofi.saves.current?.table.match.houses == [2, 9] }
        p.kofi.closeApp()
        await until("Ama sees him reconnecting") { p.ama.session.isReconnecting }
        // Her turn, but the board takes no move while he is away.
        XCTAssertFalse(p.ama.session.humanToMove)

        let kofi = p.kofi.openApp()
        XCTAssertTrue(kofi.play.rejoin())
        await until("back") { kofi.session.link != nil && !p.ama.session.isReconnecting }
        await play(3, on: p.ama, with: kofi)
        XCTAssertEqual(kofi.session.link?.table?.match.houses, [2, 9, 3])
    }

    func testTheCreatorClosesTheAppAndIsInChargeAgain() async throws {
        let p = await started(newRelay())
        await play(2, on: p.ama, with: p.kofi)
        await until("saved") { p.ama.saves.current?.table.match.houses == [2] }
        p.ama.closeApp()
        await until("Kofi sees her reconnecting") { p.kofi.session.isReconnecting }

        let ama = p.ama.openApp()
        XCTAssertEqual(ama.play.saved?.seat, 0)
        XCTAssertTrue(ama.play.rejoin())
        await until("she is back") { ama.session.link != nil }
        XCTAssertEqual(ama.session.link?.isHost, true, "her phone is in charge again")
        XCTAssertEqual(ama.session.remoteGame, RemoteGame(mySide: .south, opponentName: "Kofi", via: .online))
        XCTAssertEqual(ama.session.state, p.kofi.session.state, "from her saved match")
        await until("both see each other") { !ama.session.isReconnecting && !p.kofi.session.isReconnecting }

        // His move goes to her new room, and hers comes back from it.
        await play(9, on: p.kofi, with: ama)
        await play(3, on: ama, with: p.kofi)
        XCTAssertEqual(ama.session.link?.table?.match.houses, [2, 9, 3])
        XCTAssertEqual(ama.session.link?.table?.stateHash, p.kofi.session.link?.table?.stateHash)
    }

    func testBothCloseTheAppAndTheGameGoesOnWhenBothAreBack() async throws {
        let p = await started(newRelay())
        await play(2, on: p.ama, with: p.kofi)
        await until("saved") { p.ama.saves.current?.table.match.houses == [2] && p.kofi.saves.current?.table.match.houses == [2] }
        p.ama.closeApp()
        p.kofi.closeApp()

        // He is back first, and waits: her phone applies the moves.
        let kofi = p.kofi.openApp()
        XCTAssertTrue(kofi.play.rejoin())
        await until("he is in, waiting for her") { kofi.session.link != nil }
        XCTAssertTrue(kofi.session.isReconnecting)
        XCTAssertFalse(kofi.session.humanToMove, "no move until she is back")
        XCTAssertEqual(kofi.session.state.moveNumber, 1, "his saved board meanwhile")

        let ama = p.ama.openApp()
        XCTAssertTrue(ama.play.rejoin())
        await until("both back") { ama.session.link != nil && !ama.session.isReconnecting && !kofi.session.isReconnecting }
        await play(9, on: kofi, with: ama)
        await play(3, on: ama, with: kofi)
    }

    func testTheInvitationLinkForTheSavedGameRejoinsIt() async throws {
        let p = await started(newRelay(codes: ["K7M2QD"]))
        await play(2, on: p.ama, with: p.kofi)
        await until("saved") { p.kofi.saves.current?.table.match.houses == [2] }
        p.kofi.closeApp()

        let kofi = p.kofi.openApp()
        XCTAssertFalse(kofi.play.rejoins(link: OnlineConfig.joinLink("ZZZZZZ")), "another game's link is an invitation as before")
        XCTAssertTrue(kofi.play.rejoins(link: OnlineConfig.joinLink("K7M2QD")))
        XCTAssertTrue(kofi.play.open(link: OnlineConfig.joinLink("K7M2QD"), name: "Kofi"))
        await until("back in the same game, in his own seat") { kofi.session.link != nil && !kofi.session.isReconnecting }
        XCTAssertEqual(kofi.session.remoteGame?.mySide, .north)
        XCTAssertEqual(kofi.session.state.moveNumber, 1)
        XCTAssertFalse(kofi.play.rejoins(link: OnlineConfig.joinLink("K7M2QD")), "already in it")
    }

    // MARK: - When it cannot be rejoined

    func testAGameThatHasGoneSaysSoAndTheSaveIsRemoved() async throws {
        let p = await started(newRelay())
        await until("saved") { p.kofi.saves.current != nil }
        p.kofi.closeApp()
        // The room closed while he was away (a day went by, or she left): the relay knows no such game.
        let kofi = p.kofi.openApp(dial: newRelay().dial)
        var opened = false
        kofi.lobby.onStart = { opened = true }
        XCTAssertTrue(kofi.play.rejoin())
        await until("told") { kofi.play.rejoining == .failed(OnlinePlay.gameEnded) }
        XCTAssertEqual(OnlinePlay.gameEnded, "That game has ended.")
        XCTAssertNil(kofi.saves.current)
        XCTAssertNil(kofi.play.saved)
        XCTAssertNil(kofi.secrets.read(OnlineSaves.secretsKey))
        XCTAssertFalse(opened)
        XCTAssertNil(kofi.session.link)
        kofi.play.dismissRejoinProblem()
        XCTAssertEqual(kofi.play.rejoining, .no)
    }

    /// A relay socket that answers whatever is sent with one refusal.
    private final class Refusing: RelaySocket, @unchecked Sendable {
        let incoming: AsyncStream<String>
        private let out: AsyncStream<String>.Continuation
        private let reason: String

        init(reason: String) {
            self.reason = reason
            (incoming, out) = AsyncStream.makeStream()
        }

        func send(_ text: String) async throws { out.yield(#"{"type":"refused","reason":"\#(reason)"}"#) }
        func close() { out.finish() }
    }

    private func refusing(_ reason: String) -> OnlineTransport.Dial { { Refusing(reason: reason) } }

    func testAReasonTheAppDoesNotKnowAlsoEndsTheGame() async throws {
        let p = await started(newRelay())
        await until("saved") { p.kofi.saves.current != nil }
        p.kofi.closeApp()
        let kofi = p.kofi.openApp(dial: refusing("somethingFromANewerRelay"))
        XCTAssertTrue(kofi.play.rejoin())
        await until("told") { kofi.play.rejoining == .failed("That game has ended.") }
        XCTAssertNil(kofi.saves.current)
    }

    func testWhileOnlinePlayIsRestingTheGameIsKeptForLater() async throws {
        let p = await started(newRelay())
        await until("saved") { p.kofi.saves.current != nil }
        p.kofi.closeApp()
        let kofi = p.kofi.openApp(dial: refusing("paused"))
        XCTAssertTrue(kofi.play.rejoin())
        await until("told") { kofi.play.rejoining == .failed("Online play is resting. Try again later.") }
        XCTAssertNotNil(kofi.saves.current, "it may still be there when online play is back")
    }

    func testEveryRefusalToRejoinHasPlainWords() {
        for reason in RelayEvent.Refusal.allCases {
            let answer = OnlinePlay.rejoinRefused(reason)
            XCTAssertFalse(answer.message.isEmpty)
            for word in ["relay", "server", "room", "host", "client", "lobby", "token"] {
                XCTAssertFalse(answer.message.lowercased().contains(word), answer.message)
            }
        }
        XCTAssertTrue(OnlinePlay.rejoinRefused(.notFound).ended)
        XCTAssertTrue(OnlinePlay.rejoinRefused(.other).ended)
        XCTAssertFalse(OnlinePlay.rejoinRefused(.paused).ended)
        XCTAssertFalse(OnlinePlay.rejoinRefused(.tooMany).ended)
    }

    func testLeaveGameOnTheCardRemovesTheSaveAndTellsTheOtherPlayer() async throws {
        let p = await started(newRelay())
        await until("saved") { p.kofi.saves.current != nil }
        p.kofi.closeApp()
        await until("Ama sees him reconnecting") { p.ama.session.isReconnecting }

        let kofi = p.kofi.openApp()
        kofi.play.leaveSaved()
        XCTAssertNil(kofi.play.saved, "gone from Home at once")
        XCTAssertNil(kofi.saves.current)
        await until("Ama is told he left") { p.ama.session.opponentLeft }
        XCTAssertNil(p.ama.saves.current)
    }

    func testAGameWhoseOtherPlayerLeftWhileTheAppWasClosedHasEnded() async throws {
        let relay = newRelay()
        let p = await started(relay)
        await until("saved") { p.kofi.saves.current != nil }
        p.kofi.closeApp()
        p.ama.session.leaveNearbyGame()   // she made the game: it closes with her
        await until("closed") { await !relay.hasRoom(p.kofi.saves.current?.code ?? "") }

        let kofi = p.kofi.openApp()
        XCTAssertTrue(kofi.play.rejoin())
        await until("told") { kofi.play.rejoining == .failed("That game has ended.") }
        XCTAssertNil(kofi.saves.current)
    }

    // MARK: - Ninety seconds

    private let clock = ManualClock()

    private struct Pair {
        let host: GameSession
        let guest: GameSession
        let hostLink: MatchLink
        let guestLink: MatchLink
        let guestTransport: LoopbackTransport
    }

    /// Two sessions with online timing and a clock the test moves.
    private func onlinePair() async -> Pair {
        let host = TestSupport.session(), guest = TestSupport.session()
        let hostTransport = LoopbackTransport(), guestTransport = LoopbackTransport()
        let hostLink = MatchLink(hosting: OwareMatch(rules: .abapa), name: "Ama", transport: hostTransport, clock: clock, timing: .online)
        let guestLink = MatchLink(joiningAs: "Kofi", transport: guestTransport, clock: clock, timing: .online)
        host.startRemote(hostLink, via: .online)
        guest.startRemote(guestLink, via: .online)
        hostTransport.connect(guestTransport)
        await until("Kofi asks to join") { hostLink.joinRequests.count == 1 }
        await hostLink.accept(hostLink.joinRequests[0].peer)
        await until("both seated") { host.remoteGame?.opponentName == "Kofi" && guest.remoteGame?.opponentName == "Ama" }
        await hostLink.ready()
        await guestLink.ready()
        await until("both ready") { host.isStarted && guest.isStarted }
        return Pair(host: host, guest: guest, hostLink: hostLink, guestLink: guestLink, guestTransport: guestTransport)
    }

    func testNinetySecondsOfSilenceAsksThePlayerButKeepsTheGame() async {
        let p = await onlinePair()
        p.host.play(house: 2)
        await until("Kofi sees the move") { p.guest.state.moveNumber == 1 }
        p.guestTransport.isQuiet = true

        clock.advance(by: 30)
        await p.hostLink.tick()
        XCTAssertTrue(p.host.isReconnecting)
        XCTAssertFalse(p.host.offersComputer)
        clock.advance(by: 61)
        await p.hostLink.tick()
        XCTAssertTrue(p.host.offersComputer, "the player is asked: wait, the computer, or leave")
        XCTAssertTrue(p.host.keepsSeatWhileWaiting, "and may keep waiting")
        XCTAssertNotNil(p.host.link, "the game is still on")
        XCTAssertEqual(p.host.link?.room.seats[1]?.name, "Kofi", "his seat is kept")

        p.host.keepWaiting()
        XCTAssertFalse(p.host.offersComputer)
        XCTAssertTrue(p.host.isReconnecting, "still waiting, and saying so")
        XCTAssertFalse(p.host.humanToMove)

        // Minutes later he is back, and they play on.
        clock.advance(by: 240)
        p.guestTransport.isQuiet = false
        await p.guestLink.tick()
        await until("Kofi is back") { !p.host.isReconnecting }
        XCTAssertFalse(p.host.offersComputer)
        XCTAssertFalse(p.host.opponentGone)
        p.guest.play(house: 9)
        await until("the game goes on") { p.host.state.moveNumber == 2 && p.guest.state.moveNumber == 2 }
    }

    func testThePlayerWhoKeepsWaitingIsAskedAgainLater() async {
        let p = await onlinePair()
        p.guestTransport.isQuiet = true
        clock.advance(by: 91)
        await p.hostLink.tick()
        p.host.keepWaiting()
        clock.advance(by: 60)
        await p.hostLink.tick()
        XCTAssertFalse(p.host.offersComputer, "not yet")
        clock.advance(by: 31)
        await p.hostLink.tick()
        XCTAssertTrue(p.host.offersComputer, "another ninety seconds: asked again")
    }

    func testAfterNinetySecondsThePlayerMayStillChooseTheComputerOrLeave() async {
        let p = await onlinePair()
        p.guestTransport.isQuiet = true
        clock.advance(by: 91)
        await p.hostLink.tick()
        p.host.finishAgainstComputer(difficulty: .beginner)
        XCTAssertEqual(p.host.mode, .versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south))
        XCTAssertNil(p.host.link)

        let q = await onlinePair()
        q.guestTransport.isQuiet = true
        clock.advance(by: 91)
        await q.guestLink.tick()
        XCTAssertTrue(q.guest.offersComputer, "the joining phone is asked too")
        q.guest.leaveNearbyGame()
        XCTAssertNil(q.guest.link)
    }

    func testNearbyStillGivesUpAfterFifteenSeconds() async {
        let host = TestSupport.session()
        let hostTransport = LoopbackTransport(), guestTransport = LoopbackTransport()
        let hostLink = MatchLink(hosting: OwareMatch(rules: .abapa), name: "Ama", transport: hostTransport, clock: clock)
        let guestLink = MatchLink(joiningAs: "Kofi", transport: guestTransport, clock: clock)
        host.startRemote(hostLink)
        hostTransport.connect(guestTransport)
        await until("Kofi asks to join") { hostLink.joinRequests.count == 1 }
        await hostLink.accept(hostLink.joinRequests[0].peer)
        await until("seated") { guestLink.room.mySeat == 1 }
        await hostLink.ready()
        await guestLink.ready()
        await until("started") { host.isStarted }
        guestTransport.isQuiet = true
        clock.advance(by: 16)
        await hostLink.tick()
        XCTAssertTrue(host.offersComputer)
        XCTAssertFalse(host.keepsSeatWhileWaiting, "side by side there is no Keep waiting")
        XCTAssertNil(hostLink.room.seats[1])
    }

    // MARK: - Who this phone is

    func testTheInstallIDIsMadeOnceAndKeptInTheKeychain() {
        let secrets = MemorySecrets(), defaults = TestSupport.defaults()
        let id = OnlineConfig.installID(secrets: secrets, defaults: defaults)
        XCTAssertEqual(id.count, 32)
        XCTAssertEqual(OnlineConfig.installID(secrets: secrets, defaults: defaults), id, "the same every time")
        XCTAssertEqual(secrets.read(OnlineConfig.installKey).map { String(decoding: $0, as: UTF8.self) }, id)
        XCTAssertNil(defaults.string(forKey: OnlineConfig.installKey), "not in the settings file")
        XCTAssertEqual(OnlineConfig.installID(secrets: secrets, defaults: TestSupport.defaults()), id, "it outlives the settings")
    }

    func testAnInstallIDFromAnEarlierBuildMovesToTheKeychainUnchanged() {
        let secrets = MemorySecrets(), defaults = TestSupport.defaults()
        defaults.set("0123456789abcdef0123456789abcdef", forKey: OnlineConfig.installKey)
        XCTAssertEqual(OnlineConfig.installID(secrets: secrets, defaults: defaults), "0123456789abcdef0123456789abcdef")
        XCTAssertNil(defaults.string(forKey: OnlineConfig.installKey), "moved, not copied")
        XCTAssertEqual(OnlineConfig.installID(secrets: secrets, defaults: defaults), "0123456789abcdef0123456789abcdef")
    }

    /// If the Keychain cannot be written, an ID already saved is not thrown away.
    func testAnInstallIDIsNotLostWhenTheKeychainCannotBeWritten() {
        let secrets = MemorySecrets(), defaults = TestSupport.defaults()
        secrets.refusesWrites = true
        defaults.set("0123456789abcdef0123456789abcdef", forKey: OnlineConfig.installKey)
        XCTAssertEqual(OnlineConfig.installID(secrets: secrets, defaults: defaults), "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(defaults.string(forKey: OnlineConfig.installKey), "0123456789abcdef0123456789abcdef")
    }

    func testTheKeychainKeepsReplacesAndRemovesAValue() throws {
        let keychain = Keychain(service: "OwareTests.\(UUID().uuidString)")
        defer { keychain.remove("seat") }
        guard keychain.write(Data("one".utf8), for: "seat") else {
            throw XCTSkip("this build cannot use the Keychain (not signed)")
        }
        XCTAssertEqual(keychain.read("seat"), Data("one".utf8))
        XCTAssertTrue(keychain.write(Data("two".utf8), for: "seat"))
        XCTAssertEqual(keychain.read("seat"), Data("two".utf8))
        XCTAssertNil(keychain.read("other"))
        keychain.remove("seat")
        XCTAssertNil(keychain.read("seat"))
    }

    // MARK: - The demo player

    /// `--online-demo`: the relay inside the app is new each launch, so the saved game's room is
    /// made again and Ama comes back to it, as a friend still in the game would be.
    func testInTheDemoAmaIsStillThereAfterTheAppIsClosed() async throws {
        let script = DemoPlayer.Script(thinkTime: 0.01, joinDelay: 0.01)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secrets = MemorySecrets()
        let first = OnlinePlay(session: TestSupport.session(), network: .demo(script: script),
                               saves: OnlineSaves(directory: folder, secrets: secrets))
        first.lobby.onStart = {}
        first.lobby.start(name: "Kofi", rules: .abapa)
        await until("Ama is ready") { first.lobby.opponent?.isReady == true }
        await first.lobby.ready()
        await until("the game starts") { first.lobby.session.isStarted }
        first.lobby.session.play(house: 2)
        await until("Ama answers") { first.lobby.session.state.moveNumber >= 2 && first.lobby.session.humanToMove }
        await until("saved") { first.saves?.current?.table.match.houses.count == 2 }
        (first.lobby.network as? OnlineNetwork)?.transport?.abandon()
        first.lobby.session.link?.room.stop()
        first.lobby.network.shutDown()

        let again = OnlinePlay(session: TestSupport.session(), network: .demo(script: script),
                               saves: OnlineSaves(directory: folder, secrets: secrets))
        again.lobby.onStart = {}
        XCTAssertEqual(again.saved?.opponentName, "Ama")
        XCTAssertTrue(again.rejoin())
        await until("back in the game") { again.lobby.session.link != nil }
        XCTAssertEqual(again.lobby.session.state.moveNumber, 2)
        await until("Ama is there") { !again.lobby.session.isReconnecting }
        await until("my turn") { again.lobby.session.humanToMove }
        let house = try XCTUnwrap(again.lobby.session.state.legalMoves().first).absoluteIndex
        again.lobby.session.play(house: house)
        await until("and she answers") { again.lobby.session.state.moveNumber >= 4 }
        again.lobby.cancel()
    }
}
