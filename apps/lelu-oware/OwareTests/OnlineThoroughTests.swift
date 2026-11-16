import MatchKit
import MatchKitOnline
import OwareEngine
import XCTest
@testable import Oware

/// A thorough pass over online play, as a player would live it: inviting and being invited,
/// leaving and coming back, games won and lost and played again, and how it holds up on a slow or
/// patchy connection. Two phones, each with its own lobby, session and board, through the relay in
/// memory (`LocalRelay`) or, when `RELAY_URL` is given, a real one.
@MainActor
final class OnlineThoroughTests: XCTestCase {
    // MARK: - Helpers

    override func setUp() {
        super.setUp()
        // One thing going wrong is the finding; what follows it would only be noise.
        continueAfterFailure = false
    }

    /// Where two phones stand, for a failure message.
    private func describe(_ ama: Phone, _ kofi: Phone) -> String {
        func one(_ p: Phone) -> String {
            let s = p.session
            let status = p.transport.map { "\($0.status)".prefix(12) } ?? "no transport"
            return "move \(s.state.moveNumber) toMove \(s.state.sideToMove.label) human \(s.humanToMove) animating \(s.isAnimating) "
                + "reconnecting \(s.isReconnecting) gone \(s.opponentGone) link \(status) "
                + "seats \(p.lobby.session.link?.room.seats.mapValues { $0.isReconnecting }.description ?? "-") "
                + "table \(s.link?.table?.match.houses.count ?? -1)"
        }
        return " | Ama: \(one(ama)) | Kofi: \(one(kofi))"
    }

    private func until(_ what: @autoclosure () -> String, timeout: TimeInterval = 8, _ condition: () async -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > end { return XCTFail("timed out waiting: \(what())") }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func settle(_ seconds: Double = 0.08) async { try? await Task.sleep(for: .seconds(seconds)) }

    struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    /// One phone: its Play online, and what it told analytics.
    @MainActor
    final class Phone {
        let play: OnlinePlay
        var tracked: [AnalyticsEvent] = []
        var lobby: NearbyLobby { play.lobby }
        var session: GameSession { play.lobby.session }
        var transport: OnlineTransport? { (play.lobby.network as? OnlineNetwork)?.transport }

        init(dial: @escaping OnlineTransport.Dial, install: String) {
            var sink: ((AnalyticsEvent) -> Void)?
            let session = TestSupport.session(track: { sink?($0) })
            play = OnlinePlay(session: session,
                              network: OnlineNetwork(dial: dial, install: install, retryDelays: [0.01, 0.01, 0.02]))
            play.lobby.onStart = {}
            sink = { [weak self] in self?.tracked.append($0) }
        }
    }

    private func phone(_ relay: LocalRelay, _ install: String) -> Phone { Phone(dial: relay.dial, install: install) }

    /// Ama invites, Kofi joins with her code, both press Ready: the game is on.
    private func started(_ relay: LocalRelay, rules: RuleSet = .namNam,
                         ama: Phone? = nil, kofi: Phone? = nil) async -> (ama: Phone, kofi: Phone) {
        let ama = ama ?? phone(relay, "ama"), kofi = kofi ?? phone(relay, "kofi")
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

    /// Plays moves chosen by `rng` until the game ends or `limit` moves, checking both phones
    /// against the same moves on a board of their own after each. `between` runs before each move.
    @discardableResult
    private func playOn(_ p: (ama: Phone, kofi: Phone), from start: GameState? = nil, seed: UInt64 = 1, limit: Int = 400,
                        timeout: TimeInterval = 10, between: (Int) async -> Void = { _ in }) async throws -> GameState {
        var alone = start ?? p.ama.session.state
        var rng = LCG(s: seed)
        var plies = 0
        while !alone.isOver, plies < limit {
            await between(plies)
            let mover = alone.sideToMove == p.ama.session.remoteGame?.mySide ? p.ama.session : p.kofi.session
            await until("move \(plies + 1): the mover's turn", timeout: timeout) { mover.humanToMove }
            let move = try XCTUnwrap(alone.legalMoves().randomElement(using: &rng))
            alone = try alone.applying(move).state
            mover.play(house: move.absoluteIndex)
            plies += 1
            await until("move \(plies) on both phones", timeout: timeout) {
                p.ama.session.state == alone && p.kofi.session.state == alone
            }
        }
        return alone
    }

    // MARK: - 1. Inviting

    func testInvitingAgainAfterCancellingGivesANewGameAndClosesTheOld() async {
        let relay = LocalRelay(codes: ["K7M2QD", "ABCDEF"])
        let ama = phone(relay, "ama")
        ama.lobby.start(name: "Ama", rules: .namNam)
        await until("first code") { ama.lobby.roomCode == "K7M2QD" }
        ama.lobby.cancel()
        await until("the first game is gone") { await !relay.hasRoom("K7M2QD") }
        ama.lobby.start(name: "Ama", rules: .namNam)
        await until("second code") { ama.lobby.roomCode == "ABCDEF" }

        // The old invitation no longer works; the new one does.
        let kofi = phone(relay, "kofi")
        XCTAssertTrue(kofi.lobby.join(code: "K7M2QD", name: "Kofi"))
        await until("the old code is refused") { kofi.lobby.phase == .refused(OnlineNetwork.explain(.notFound)) }
        kofi.lobby.cancel()
        XCTAssertTrue(kofi.lobby.join(code: "ABCDEF", name: "Kofi"))
        await until("the new one joins") { ama.lobby.opponent?.name == "Kofi" }
    }

    func testAfterNotNowTheNextFriendJoinsAndPlays() async throws {
        let relay = LocalRelay()
        let ama = phone(relay, "ama"), kofi = phone(relay, "kofi"), yaw = phone(relay, "yaw")
        ama.lobby.start(name: "Ama", rules: .abapa)
        await until("code") { ama.lobby.roomCode != nil }
        let code = ama.lobby.roomCode ?? ""
        XCTAssertTrue(kofi.lobby.join(code: code, name: "Kofi"))
        await until("Kofi asks") { ama.lobby.opponent?.name == "Kofi" }
        await ama.lobby.notNow()
        await until("Kofi is told") { kofi.lobby.phase == .refused("They said not this time.") }
        kofi.lobby.cancel()

        XCTAssertTrue(yaw.lobby.join(code: code, name: "Yaw"))
        await until("Yaw is in") { ama.lobby.opponent?.name == "Yaw" && yaw.lobby.opponent?.isConnected == true }
        await ama.lobby.ready()
        await yaw.lobby.ready()
        await until("they play") { ama.session.isStarted && yaw.session.isStarted }
        XCTAssertEqual(ama.session.remoteGame?.opponentName, "Yaw")
        try await playOn((ama, yaw), limit: 6)
    }

    func testAFriendWhoBacksOutBeforeReadyCanComeStraightBack() async {
        let relay = LocalRelay()
        let ama = phone(relay, "ama"), kofi = phone(relay, "kofi")
        ama.lobby.start(name: "Ama", rules: .namNam)
        await until("code") { ama.lobby.roomCode != nil }
        let code = ama.lobby.roomCode ?? ""
        for visit in 1...3 {
            XCTAssertTrue(kofi.lobby.join(code: code, name: "Kofi"))
            await until("visit \(visit): Ama sees Kofi") { ama.lobby.phase == .ready && ama.lobby.opponent?.name == "Kofi" }
            await until("visit \(visit): Kofi is in") { kofi.lobby.opponent?.isConnected == true }
            kofi.lobby.cancel()
            await until("visit \(visit): Ama is waiting again") { ama.lobby.phase == .waiting && ama.lobby.opponent == nil }
            XCTAssertEqual(ama.lobby.roomCode, code, "the same invitation still stands")
        }
    }

    // MARK: - 2. Being invited

    func testAnInvitationWhoseSenderGaveUpSaysSo() async {
        let relay = LocalRelay()
        let ama = phone(relay, "ama"), kofi = phone(relay, "kofi")
        ama.lobby.start(name: "Ama", rules: .namNam)
        await until("code") { ama.lobby.roomCode != nil }
        let link = OnlineConfig.joinLink(ama.lobby.roomCode ?? "")
        ama.lobby.cancel()
        await until("gone") { await !relay.hasRoom(RoomCode(link: link)?.text ?? "") }
        XCTAssertTrue(kofi.play.open(link: link, name: "Kofi"))
        await until("told") { kofi.lobby.phase == .refused(OnlineNetwork.explain(.notFound)) }
    }

    /// A second invitation tapped while looking at the first one's Ready screen: the first is
    /// left, the second joined.
    func testASecondInvitationReplacesOneNotYetStarted() async {
        let relay = LocalRelay(codes: ["K7M2QD", "ABCDEF"])
        let ama = phone(relay, "ama"), yaw = phone(relay, "yaw"), kofi = phone(relay, "kofi")
        ama.lobby.start(name: "Ama", rules: .namNam)
        yaw.lobby.start(name: "Yaw", rules: .abapa)
        await until("two games") { ama.lobby.roomCode != nil && yaw.lobby.roomCode != nil }
        XCTAssertTrue(kofi.play.open(link: OnlineConfig.joinLink(ama.lobby.roomCode ?? ""), name: "Kofi"))
        await until("in Ama's") { ama.lobby.opponent?.name == "Kofi" }
        XCTAssertTrue(kofi.play.open(link: OnlineConfig.joinLink(yaw.lobby.roomCode ?? ""), name: "Kofi"))
        await until("in Yaw's") { yaw.lobby.opponent?.name == "Kofi" && kofi.lobby.opponent?.name == "Yaw" }
        await until("and out of Ama's") { ama.lobby.phase == .waiting && ama.lobby.opponent == nil }
        XCTAssertEqual(kofi.lobby.gameVariant, .abapa)
    }

    func testAGameAlreadyBeingPlayedCannotBeJoined() async {
        let relay = LocalRelay()
        let p = await started(relay)
        let yaw = phone(relay, "yaw")
        XCTAssertTrue(yaw.lobby.join(code: p.ama.lobby.roomCode ?? "", name: "Yaw"))
        await until("told") { yaw.lobby.phase == .refused(OnlineNetwork.explain(.full)) }
        XCTAssertTrue(p.ama.session.isStarted && p.kofi.session.isStarted)
    }

    // MARK: - 3. Leaving and coming back

    /// Kofi's connection breaks five times in one game, sometimes in the middle of a sowing. Each
    /// time his phone takes its seat back and the game carries on from where it was.
    func testAConnectionThatKeepsBreakingStillFinishesTheGame() async throws {
        let relay = LocalRelay()
        let p = await started(relay, rules: .namNam)
        let slowA = OnlinePairTests.SlowBoard(seconds: 0.02), slowK = OnlinePairTests.SlowBoard(seconds: 0.03)
        p.ama.session.attach(slowA)
        p.kofi.session.attach(slowK)
        var breaks = 0
        let end = try await playOn(p, seed: 9, limit: 40, timeout: 15) { ply in
            guard ply > 0, ply % 7 == 0 else { return }
            breaks += 1
            // Odd breaks are Kofi's, even ones Ama's; every third comes mid-sowing.
            if breaks % 3 != 0 { await self.until("still") { !p.ama.session.isAnimating && !p.kofi.session.isAnimating } }
            await relay.cut(breaks % 2 == 1 ? PeerID("p1") : Relay.creator, in: "K7M2QD")
        }
        XCTAssertGreaterThanOrEqual(breaks, 5)
        XCTAssertEqual(p.ama.session.state, end)
        XCTAssertEqual(p.kofi.session.state, end)
        await until("nobody left reconnecting") { !p.ama.session.isReconnecting && !p.kofi.session.isReconnecting }
        let rejoins = await relay.received["rejoin"] ?? 0
        XCTAssertGreaterThanOrEqual(rejoins, breaks)
        XCTAssertFalse(p.ama.session.opponentGone || p.kofi.session.opponentGone)
    }

    /// Both phones lose signal at once, a move is made in the dark, and both return.
    func testBothPhonesOfflineThenBack() async throws {
        let relay = LocalRelay()
        let p = await started(relay, rules: .abapa)
        var state = try await playOn(p, seed: 2, limit: 5)
        for _ in 0..<3 {
            await relay.setReachable(false, cutting: true)
            await until("both know") { p.ama.session.isReconnecting && p.kofi.session.isReconnecting }
            XCTAssertFalse(p.ama.session.humanToMove || p.kofi.session.humanToMove, "no move while the other is unreachable")
            await settle()
            await relay.setReachable(true)
            await until("both back") { !p.ama.session.isReconnecting && !p.kofi.session.isReconnecting }
            state = try await playOn(p, from: state, seed: 4, limit: 4)
        }
    }

    /// Kofi leaves for good in the middle. Ama is told at once, is offered the computer, and
    /// finishes the same position against it. Kofi's phone is clean for his next game.
    func testWhenAPlayerLeavesTheOtherFinishesAgainstTheComputerAndBothCanPlayAgain() async throws {
        let relay = LocalRelay(codes: ["K7M2QD", "ABCDEF"])
        let p = await started(relay, rules: .abapa)
        let position = try await playOn(p, seed: 6, limit: 9)
        p.kofi.session.leaveNearbyGame()
        await until("Ama is told he left") { p.ama.session.opponentLeft && p.ama.session.offersComputer }
        XCTAssertNil(p.kofi.session.link)

        p.ama.session.finishAgainstComputer()
        XCTAssertEqual(p.ama.session.state.houses, position.houses, "the same position, now against the computer")
        XCTAssertNil(p.ama.session.remoteGame)
        XCTAssertNil(p.ama.session.link)
        await until("her relay room is closed") { await !relay.hasRoom("K7M2QD") }

        // Both go straight into a new online game with each other.
        p.kofi.lobby.prepare(demo: false)
        p.ama.lobby.prepare(demo: false)
        let again = await started(relay, rules: .namNam, ama: p.kofi, kofi: p.ama)
        XCTAssertEqual(again.ama.lobby.roomCode, "ABCDEF")
        XCTAssertEqual(again.kofi.session.remoteGame?.opponentName, "Ama", "Kofi invited this time: he is 'Ama' the creator here")
        try await playOn(again, limit: 6)
    }

    /// The player who left taps the old invitation again. The game went on without him (or
    /// stopped): he is told, not left looking at "Connecting…" for ever.
    func testComingBackToAGameYouLeftIsAnsweredNotLeftHanging() async throws {
        let relay = LocalRelay()
        let p = await started(relay, rules: .abapa)
        try await playOn(p, seed: 3, limit: 4)
        let link = OnlineConfig.joinLink(p.ama.lobby.roomCode ?? "")
        p.kofi.session.leaveNearbyGame()
        await until("Ama is told") { p.ama.session.opponentLeft }

        XCTAssertTrue(p.kofi.play.open(link: link, name: "Kofi"))
        await until("Kofi gets an answer") {
            if case .refused = p.kofi.lobby.phase { return true }
            return false
        }
        XCTAssertEqual(p.kofi.lobby.phase, .refused("That game has already started."))
        XCTAssertTrue(p.ama.session.offersComputer, "Ama's choice is still hers to make")
    }

    func testWhenTheInviterLeavesTheFriendIsToldAndTheInvitationIsDead() async throws {
        let relay = LocalRelay()
        let p = await started(relay, rules: .namNam)
        try await playOn(p, seed: 8, limit: 3)
        p.ama.session.leaveNearbyGame()
        await until("Kofi is told") { p.kofi.session.opponentLeft && p.kofi.session.offersComputer }
        await until("the game is gone from the relay") { await !relay.hasRoom("K7M2QD") }
        p.kofi.session.finishAgainstComputer()
        XCTAssertNil(p.kofi.session.remoteGame)
        XCTAssertEqual(p.kofi.session.mode.aiSide, .south, "he keeps his side; the computer takes hers")
    }

    // MARK: - 4. Winning, losing, playing again

    /// Whole games to the end in each rule set: the same result on both phones, and each phone
    /// records its own side of it once.
    func testGamesPlayedToTheEndAreWonAndLostTheSameOnBothPhones() async throws {
        for (rules, seeds) in [(RuleSet.abapa, [UInt64(1), 2, 3]), (.namNam, [4, 5])] {
            for seed in seeds {
                let relay = LocalRelay()
                let p = await started(relay, rules: rules)
                let end = try await playOn(p, seed: seed, limit: 6_000, timeout: 15)
                XCTAssertTrue(end.isOver, "\(rules.variant) seed \(seed): the game ended (\(end.moveNumber) moves)")
                let outcome = try XCTUnwrap(end.outcome)
                XCTAssertEqual(p.ama.session.state.outcome, outcome)
                XCTAssertEqual(p.kofi.session.state.outcome, outcome)

                func result(_ phone: Phone) -> [String] {
                    phone.tracked.compactMap { if case let .onlineFinished(result, _) = $0 { result } else { nil } }
                }
                await until("\(rules.variant) seed \(seed): both phones record the result") {
                    result(p.ama).count == 1 && result(p.kofi).count == 1
                }
                let expected: (String, String) = switch outcome.winner {
                case .south?: ("win", "loss")
                case .north?: ("loss", "win")
                case nil: ("draw", "draw")
                }
                XCTAssertEqual(result(p.ama), [expected.0], "\(rules.variant) seed \(seed): Ama (South)")
                XCTAssertEqual(result(p.kofi), [expected.1], "\(rules.variant) seed \(seed): Kofi (North)")
                p.ama.lobby.cancel()
                p.kofi.lobby.cancel()
            }
        }
    }

    /// Three games in a row with a rematch between each: the other player starts each new game,
    /// nobody presses Ready again, and every game is recorded.
    func testRematchesSwapWhoStartsAndEachGameCounts() async throws {
        let relay = LocalRelay()
        let p = await started(relay, rules: .abapa)
        var starter = Player.south
        for game in 1...3 {
            XCTAssertEqual(p.ama.session.state.sideToMove, starter, "game \(game): who starts")
            let end = try await playOn(p, seed: UInt64(game), limit: 600, timeout: 15)
            XCTAssertTrue(end.isOver, "game \(game) ended")
            await until("game \(game): both may ask for another") { p.ama.session.canAskRematch && p.kofi.session.canAskRematch }
            guard game < 3 else { break }
            p.ama.session.requestRematch()
            await until("game \(game): Kofi sees Ama asked") { p.kofi.session.rematchAsked.contains(.south) }
            XCTAssertTrue(p.kofi.session.state.isOver, "nothing starts until both ask")
            p.kofi.session.requestRematch()
            await until("game \(game + 1) starts on both phones") {
                !p.ama.session.state.isOver && !p.kofi.session.state.isOver
                    && p.ama.session.state.moveNumber == 0 && p.kofi.session.state.moveNumber == 0
            }
            XCTAssertTrue(p.ama.session.isStarted && p.kofi.session.isStarted, "no second Ready")
            starter = starter.opponent
        }
        func finished(_ phone: Phone) -> Int { phone.tracked.filter { if case .onlineFinished = $0 { true } else { false } }.count }
        await until("three results each") { finished(p.ama) == 3 && finished(p.kofi) == 3 }
    }

    func testResigningGivesTheOtherPlayerTheWinAndARematchStillWorks() async throws {
        let relay = LocalRelay()
        let p = await started(relay, rules: .namNam)
        try await playOn(p, seed: 12, limit: 5)
        await until("Kofi may resign") { p.kofi.session.canEndGame }
        p.kofi.session.resign()
        await until("over on both") { p.ama.session.state.isOver && p.kofi.session.state.isOver }
        XCTAssertEqual(p.ama.session.state.outcome?.winner, .south)
        XCTAssertEqual(p.kofi.session.state.outcome?.winner, .south)

        p.kofi.session.requestRematch()
        p.ama.session.requestRematch()
        await until("a new game") { !p.ama.session.state.isOver && !p.kofi.session.state.isOver }
        XCTAssertEqual(p.ama.session.state.sideToMove, .north, "the loser of the toss last time starts")
        try await playOn(p, seed: 13, limit: 6)
    }

    func testAskingForARematchWhenTheOtherHasGoneSaysTheyLeft() async throws {
        let relay = LocalRelay()
        let p = await started(relay, rules: .abapa)
        try await playOn(p, seed: 1, limit: 600, timeout: 15)
        p.ama.session.requestRematch()
        await until("Kofi sees she asked") { p.kofi.session.rematchAsked.contains(.south) }
        p.kofi.session.leaveNearbyGame()
        await until("Ama is told") { p.ama.session.opponentLeft }
        XCTAssertFalse(p.ama.session.canAskRematch)
        XCTAssertFalse(p.ama.session.offersComputer, "the game was over: nothing to finish")
    }

    // MARK: - 5. Size and speed

    /// The whole match travels in every snapshot, so the longest games must still fit in one
    /// message with room to spare. The relay takes 32 KB less a little (it took 4 KB for Oware
    /// until this test found a 1,620-move Nam-Nam game at 4.2 KB).
    func testTheLongestGamesStillFitInOneMessage() throws {
        var longest: [RuleSet.Variant: (plies: Int, bytes: Int)] = [:]
        for rules in [RuleSet.abapa, .namNam] {
            for seed in 1...150 {
                var state = GameState.initial(rules: rules)
                var rng = LCG(s: UInt64(seed))
                var houses: [Int] = []
                while !state.isOver, houses.count < 5_000 {
                    guard let move = state.legalMoves().randomElement(using: &rng) else { break }
                    state = try state.applying(move).state
                    houses.append(move.absoluteIndex)
                }
                var table = OwareTable(match: OwareMatch(rules: rules, houses: houses), rematchAsked: [.south, .north],
                                       paces: [.south: 0.35, .north: 1.6], ready: [.south, .north])
                table.stateHash = state.fingerprint
                let message = RoomMessage<OwareTable, TableIntent>.welcome(
                    seat: 1, token: UUID(), names: [0: String(repeating: "W", count: 24), 1: String(repeating: "M", count: 24)],
                    snapshot: table)
                let envelope = try JSONEncoder().encode(Envelope(protocolVersion: MatchKit.protocolVersion, sequence: 99_999, body: message))
                let frame = try JSONEncoder().encode(RelayRequest.data(envelope, to: PeerID("p1")))
                if frame.count > longest[rules.variant]?.bytes ?? 0 { longest[rules.variant] = (houses.count, frame.count) }
            }
        }
        for (variant, worst) in longest.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("ONLINE-SIZE \(variant.rawValue): longest of 150 games \(worst.plies) moves, largest message \(worst.bytes) bytes")
            XCTAssertLessThan(worst.bytes, 16 * 1024, "\(variant.rawValue): a \(worst.plies)-move game is over half the relay's limit")
        }
    }

    /// What a game costs in messages (the relay bills by the message) and how fast a move crosses.
    func testAGameSendsFewMessagesAndAMoveCrossesQuickly() async throws {
        let relay = LocalRelay()
        let p = await started(relay, rules: .abapa)
        let before = await relay.received["data"] ?? 0
        var times: [Double] = []
        var last = Date()
        let end = try await playOn(p, seed: 2, limit: 600, timeout: 15) { ply in
            if ply > 0 { times.append(Date().timeIntervalSince(last) * 1000) }
            last = Date()
        }
        let moves = end.moveNumber
        let sent = (await relay.received["data"] ?? 0) - before
        let sorted = times.sorted()
        let median = sorted[sorted.count / 2], p95 = sorted[Int(Double(sorted.count) * 0.95)]
        print(String(format: "ONLINE-PERF in memory: %d moves, %d room messages (%.2f a move), move on both phones median %.1f ms, p95 %.1f ms",
                     moves, sent, Double(sent) / Double(moves), median, p95))
        XCTAssertLessThanOrEqual(Double(sent) / Double(moves), 2.2, "a move is one snapshot from the host, plus the guest's ask for its own")
        XCTAssertLessThan(median, 50, "a move should cross in a few milliseconds when nothing is in the way")
    }

    /// Twenty games back to back on the same two phones: nothing is left behind on the relay and
    /// the twentieth is as quick as the first.
    func testManyGamesInARowLeaveNothingBehind() async throws {
        let relay = LocalRelay(codes: [])
        let ama = phone(relay, "ama"), kofi = phone(relay, "kofi")
        var took: [Double] = []
        for game in 1...20 {
            let began = Date()
            let host = game % 2 == 1 ? ama : kofi, guest = game % 2 == 1 ? kofi : ama
            host.lobby.prepare(demo: false)
            guest.lobby.prepare(demo: false)
            let p = await started(relay, rules: game % 3 == 0 ? .namNam : .abapa, ama: host, kofi: guest)
            let code = host.lobby.roomCode ?? ""
            try await playOn(p, seed: UInt64(game), limit: 12)
            host.session.leaveNearbyGame()
            await until("game \(game): the guest is told") { guest.session.opponentLeft }
            guest.session.leaveNearbyGame()
            await until("game \(game): its room is closed") { await !relay.hasRoom(code) }
            took.append(Date().timeIntervalSince(began))
        }
        let first = took.prefix(5).reduce(0, +) / 5, last = took.suffix(5).reduce(0, +) / 5
        print(String(format: "ONLINE-PERF 20 games: first five %.0f ms each, last five %.0f ms each", first * 1000, last * 1000))
        XCTAssertLessThan(last, first * 3 + 0.5, "games do not get slower as they pile up")
    }

    // MARK: - 6. Mobile networks

    /// What a connection is like, one way: how long a message takes, how much that varies, and
    /// how often it stalls for a couple of seconds or breaks altogether.
    struct Network: Sendable {
        var name: String
        var delay: Double
        var jitter: Double
        var stallChance: Double
        var stallFor: Double
        var breakChance: Double

        /// Rough figures for a phone in town; the 3G ones are for a weak signal.
        static let wifi = Network(name: "Wi-Fi", delay: 0.008, jitter: 0.004, stallChance: 0, stallFor: 0, breakChance: 0)
        static let fiveG = Network(name: "5G", delay: 0.015, jitter: 0.008, stallChance: 0.002, stallFor: 0.3, breakChance: 0)
        static let fourG = Network(name: "4G", delay: 0.04, jitter: 0.025, stallChance: 0.01, stallFor: 0.6, breakChance: 0.002)
        static let threeG = Network(name: "3G", delay: 0.18, jitter: 0.12, stallChance: 0.04, stallFor: 1.5, breakChance: 0.01)
        static let all = [wifi, fiveG, fourG, threeG]
    }

    /// A connection with a network's delays put on it, in both directions, in order.
    final class LaggedSocket: RelaySocket, @unchecked Sendable {
        let incoming: AsyncStream<String>
        private let inner: any RelaySocket
        private let network: Network
        private let out: AsyncStream<String>.Continuation
        private var pump: Task<Void, Never>?

        init(_ inner: any RelaySocket, _ network: Network) {
            self.inner = inner
            self.network = network
            (incoming, out) = AsyncStream.makeStream()
            pump = Task { [inner, out, network] in
                for await text in inner.incoming {
                    await Self.wait(network)
                    out.yield(text)
                }
                out.finish()
            }
        }

        static func wait(_ network: Network) async {
            var seconds = max(0, network.delay + Double.random(in: -network.jitter...network.jitter))
            if Double.random(in: 0..<1) < network.stallChance { seconds += network.stallFor }
            try? await Task.sleep(for: .seconds(seconds))
        }

        func send(_ text: String) async throws {
            if Double.random(in: 0..<1) < network.breakChance {
                close()
                throw CancellationError()
            }
            await Self.wait(network)
            try await inner.send(text)
        }

        func close() {
            pump?.cancel()
            inner.close()
            out.finish()
        }
    }

    private func lagged(_ dial: @escaping OnlineTransport.Dial, _ network: Network) -> OnlineTransport.Dial {
        { LaggedSocket(try await dial(), network) }
    }

    /// The same game on Wi-Fi, 5G, 4G and a weak 3G signal (delays, stalls and breaks put on each
    /// phone's connection). It must be the same game on both phones every time; what changes is
    /// how long a move takes to show on the other phone, which is printed.
    func testAGameOnWiFi5G4GAnd3G() async throws {
        let real = ProcessInfo.processInfo.environment["RELAY_URL"].flatMap(URL.init(string:))
        let only = ProcessInfo.processInfo.environment["NETWORK"]
        for network in Network.all where only == nil || only == network.name {
            let relay = LocalRelay(codes: [])
            let dial: OnlineTransport.Dial = real.map { OnlineTransport.dial($0) } ?? relay.dial
            let ama = Phone(dial: lagged(dial, network), install: UUID().uuidString)
            let kofi = Phone(dial: lagged(dial, network), install: UUID().uuidString)
            let began = Date()
            ama.lobby.start(name: "Ama", rules: .namNam)
            await until("\(network.name): a code", timeout: 30) { ama.lobby.roomCode != nil }
            let toCode = Date().timeIntervalSince(began)
            XCTAssertTrue(kofi.lobby.join(code: ama.lobby.roomCode ?? "", name: "Kofi"))
            await until("\(network.name): Kofi is in", timeout: 30) { kofi.lobby.opponent?.isConnected == true && ama.lobby.opponent != nil }
            await kofi.lobby.ready()
            await ama.lobby.ready()
            await until("\(network.name): started", timeout: 30) { ama.session.isStarted && kofi.session.isStarted }
            let toStart = Date().timeIntervalSince(began)

            var alone = ama.session.state
            var rng = LCG(s: 21)
            var seenByOther: [Double] = [], ownBoard: [Double] = []
            for ply in 1...24 where !alone.isOver {
                let hostMoves = alone.sideToMove == .south
                let mover = hostMoves ? ama.session : kofi.session, other = hostMoves ? kofi.session : ama.session
                await until("\(network.name) move \(ply): the mover's turn" + describe(ama, kofi), timeout: 40) { mover.humanToMove }
                let move = try XCTUnwrap(alone.legalMoves().randomElement(using: &rng))
                alone = try alone.applying(move).state
                let tapped = Date()
                mover.play(house: move.absoluteIndex)
                await until("\(network.name) move \(ply): on the mover's own board", timeout: 40) { mover.state == alone }
                ownBoard.append(Date().timeIntervalSince(tapped) * 1000)
                await until("\(network.name) move \(ply): on the other phone" + describe(ama, kofi), timeout: 40) { other.state == alone }
                seenByOther.append(Date().timeIntervalSince(tapped) * 1000)
            }
            XCTAssertEqual(ama.session.state, kofi.session.state, "\(network.name): the same game on both phones")
            XCTAssertFalse(ama.session.opponentGone || kofi.session.opponentGone, "\(network.name): nobody was given up on")
            let seen = seenByOther.sorted(), own = ownBoard.sorted()
            print(String(format: "ONLINE-NET %@ (%@): code after %.2f s, playing after %.2f s; own move shows in %.0f ms; "
                         + "the other phone sees a move after median %.0f ms, slowest %.0f ms",
                         network.name, real == nil ? "relay in memory" : "real relay", toCode, toStart,
                         own[own.count / 2], seen[seen.count / 2], seen.last ?? 0))
            XCTAssertLessThan(own[own.count / 2], 100, "\(network.name): your own move never waits for the network")
            ama.session.leaveNearbyGame()
            kofi.session.leaveNearbyGame()
        }
    }
}
