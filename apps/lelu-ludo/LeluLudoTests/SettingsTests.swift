import LudoAI
import LudoEngine
import XCTest
@testable import LeluLudo

/// Rules presets, custom rules, sound and haptics: remembered, and used by new games.
@MainActor
final class SettingsTests: XCTestCase {
    func testGhanaClassicIsTheDefault() {
        let s = AppSettings(defaults: TestSupport.defaults(), testMode: false)
        XCTAssertEqual(s.preset, .ghanaClassic)
        XCTAssertEqual(s.rules, .ghanaClassic)
        XCTAssertTrue(s.soundOn && s.hapticsOn)
    }

    func testThePresetIsRemembered() {
        let d = TestSupport.defaults()
        AppSettings(defaults: d, testMode: false).preset = .classic
        let reopened = AppSettings(defaults: d, testMode: false)
        XCTAssertEqual(reopened.preset, .classic)
        XCTAssertEqual(reopened.rules, .classic)
    }

    func testCustomRulesStartFromGhanaClassicAndAreRemembered() {
        let d = TestSupport.defaults()
        let s = AppSettings(defaults: d, testMode: false)
        s.preset = .custom
        XCTAssertEqual(s.rules, .ghanaClassic, "custom starts from Ghana Classic")
        s.custom.homeKick = false
        s.custom.stacking = .safe
        let reopened = AppSettings(defaults: d, testMode: false)
        XCTAssertEqual(reopened.rules.homeKick, false)
        XCTAssertEqual(reopened.rules.stacking, .safe)
        XCTAssertFalse(reopened.rules.labourerEnabled, "Labourer stays off until it is defined")
    }

    func testTestLaunchesAreSilentWithoutChangingThePlayersChoice() {
        let s = AppSettings(defaults: TestSupport.defaults(), testMode: true)
        XCTAssertFalse(s.effectiveSound || s.effectiveHaptics)
        XCTAssertTrue(s.soundOn, "the stored choice is untouched")
    }

    func testNewGamesUseTheChosenRules() {
        let setup = GameSetup.versusComputer(opponents: 2, level: .strategist, rules: .classic)
        XCTAssertEqual(setup.rules, .classic)
        XCTAssertEqual(setup.seat(.red), .human)
        XCTAssertEqual(setup.colors, [.red, .yellow, .black], "you are red; computers sit opposite first, then beside")
        XCTAssertEqual(setup.seat(.black), .computer(.strategist))
        let together = GameSetup.passAndPlay(players: 3, rules: .ghanaClassic)
        XCTAssertEqual(together.colors, [.red, .yellow, .black])
        XCTAssertTrue(together.colors.allSatisfy { together.seat($0) == .human })
    }
}

/// What a turn sounds and feels like, recorded instead of played.
@MainActor
final class FeedbackTests: XCTestCase {
    private func session(_ state: GameState, seats: [PlayerColor: Seat], dice: [Int], feedback: RecordingFeedback) -> LudoSession {
        let store = TestSupport.store()
        store.save(SavedGame(setup: GameSetup(seats: seats), state: state, aiSeed: 1))
        let s = LudoSession(store: store, dice: ScriptedDice(dice), feedback: feedback)
        s.pacing = .instant
        return s
    }

    func testARollThenAStepPerSquare() async {
        let rec = RecordingFeedback()
        let state = GameState.arranged(players: [.red, .black], toMove: .red, tokens: [.red: [10, -1, -1, -1]])
        let s = session(state, seats: [.red: .human, .black: .human], dice: [3], feedback: rec)
        await s.roll()
        await s.tap(token: 0)
        XCTAssertEqual(rec.played, [.roll, .step, .step, .step])
    }

    func testAKickSoundsLikeOne() async {
        let rec = RecordingFeedback()
        let black = GameState.progress(of: .black, atTrackIndex: 14)
        let state = GameState.arranged(players: [.red, .black], toMove: .red, tokens: [.red: [10, -1, -1, -1], .black: [black, -1, -1, -1]])
        let s = session(state, seats: [.red: .human, .black: .human], dice: [4], feedback: rec)
        await s.roll()
        await s.tap(token: 0)
        XCTAssertEqual(rec.played.last, .kick)
    }

    func testHomeAndThreeSixes() async {
        let rec = RecordingFeedback()
        let state = GameState.arranged(players: [.red, .black], toMove: .red, tokens: [.red: [55, 56, 56, 20]])
        let s = session(state, seats: [.red: .human, .black: .human], dice: [1], feedback: rec)
        await s.roll()
        await s.tap(token: 0)
        XCTAssertTrue(rec.played.contains(.home))
        let rec2 = RecordingFeedback()
        let s2 = session(GameState.arranged(players: [.red, .black], toMove: .black, tokens: [.black: [10, -1, -1, -1]]),
                         seats: [.red: .human, .black: .computer(.novice)], dice: [6, 6, 6, 2], feedback: rec2)
        await s2.runComputerTurns()
        XCTAssertTrue(rec2.played.contains(.threeSixes))
    }
}

/// The opponents' level, changed from the game (as in Lelu Oware), and names without levels.
@MainActor
final class LevelTests: XCTestCase {
    func testTheLevelChangesForEveryComputerMidGame() {
        let store = TestSupport.store()
        let s = TestSupport.session(dice: [3], store: store)
        s.newGame(.versusComputer(opponents: 3, level: .novice, rules: .ghanaClassic))
        XCTAssertEqual(s.computerLevel, .novice)
        s.changeLevel(to: .grandmaster)
        XCTAssertEqual(s.computerLevel, .grandmaster)
        XCTAssertEqual(s.setup.seat(.green), .computer(.grandmaster))
        XCTAssertEqual(s.setup.seat(.red), .human, "you stay you")
        XCTAssertEqual(LudoSession(store: store, dice: ScriptedDice([1])).computerLevel, .grandmaster, "remembered with the game")
    }

    func testPassAndPlayHasNoLevel() {
        let s = TestSupport.session(dice: [3])
        s.newGame(.passAndPlay(players: 2, rules: .ghanaClassic))
        XCTAssertNil(s.computerLevel)
        s.changeLevel(to: .grandmaster)
        XCTAssertTrue(s.setup.colors.allSatisfy { s.setup.seat($0) == .human })
    }

    func testComputersAreNamedByColourOnly() {
        let s = TestSupport.session(dice: [3])
        s.newGame(.versusComputer(opponents: 2, level: .strategist, rules: .ghanaClassic))
        XCTAssertEqual(s.name(.black), "Black")
        XCTAssertEqual(s.name(.red), "You")
    }

    func testEveryRollIsCountedForTheBoardToShow() async {
        let s = TestSupport.session(dice: [3, 2])
        s.newGame(.passAndPlay(players: 2, rules: .ghanaClassic))
        await s.roll()
        await s.roll()
        XCTAssertEqual(s.rolls, 2)
    }
}

/// The roll said in words at the top: the 3D die shows several faces at once.
@MainActor
final class StatusTests: XCTestCase {
    func testTheRollIsSaidAsANumber() async {
        let s = TestSupport.session(dice: [6, 4])
        s.newGame(.passAndPlay(players: 2, rules: .ghanaClassic))
        XCTAssertEqual(s.status, "Red to roll")
        await s.roll()
        XCTAssertEqual(s.status, "Red rolled 6 · choose a token")
    }

    func testYourRollThenYouRolled() async {
        let s = TestSupport.session(dice: [6])
        s.newGame(.versusComputer(opponents: 1, level: .novice, rules: .ghanaClassic))
        XCTAssertEqual(s.status, "Your roll")
        await s.roll()
        XCTAssertEqual(s.status, "You rolled 6 · choose a token")
    }
}

/// App Review 5.1.1(i): the privacy policy (and support) reachable from inside the app, on Ludo's own pages.
final class LinksTests: XCTestCase {
    func testThePagesAreLeluLudosOwn() {
        for url in [Links.privacy, Links.support] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "leluoware.com")
            XCTAssertTrue(url.path.hasPrefix("/lelu-ludo/"), "not Lelu Oware's pages: \(url)")
        }
    }
}

/// Novice against the computer: a roll with one plain move forward plays itself (owner, 2026-10-04).
@MainActor
final class OnlyForwardMoveTests: XCTestCase {
    private func session(_ setup: GameSetup, red: [Int], black: [Int] = [-1, -1, -1, -1], dice: [Int]) -> LudoSession {
        let store = TestSupport.store()
        store.save(SavedGame(setup: setup, state: GameState.arranged(players: [.red, .black], toMove: .red,
                                                                     tokens: [.red: red, .black: black]), aiSeed: 1))
        return TestSupport.session(dice: dice, store: store)
    }
    private func versus(_ level: LudoAIDifficulty) -> GameSetup { GameSetup(seats: [.red: .human, .black: .computer(level)]) }

    func testNoviceMovesYourOnlyForwardMove() async {
        let s = session(versus(.novice), red: [10, -1, -1, -1], dice: [3, 2])
        await s.roll()
        XCTAssertEqual(s.state.tokens(of: .red)[0], 13, "moved by itself")
        XCTAssertEqual(s.state.toMove, .red, "and the computer has had its turn")
    }

    func testOtherLevelsLeaveItToYou() async {
        let s = session(versus(.intermediate), red: [10, -1, -1, -1], dice: [3])
        await s.roll()
        XCTAssertEqual(s.state.tokens(of: .red)[0], 10)
        XCTAssertEqual(s.movableTokens, [0], "your tap")
    }

    func testNeverInPassAndPlay() async {
        let s = session(GameSetup(seats: [.red: .human, .black: .human]), red: [10, -1, -1, -1], dice: [3])
        await s.roll()
        XCTAssertEqual(s.state.tokens(of: .red)[0], 10)
    }

    func testNotWhenThereIsAChoice() async {
        // Two tokens out: which one to move is yours to decide.
        let two = session(versus(.novice), red: [10, 20, -1, -1], dice: [3])
        await two.roll()
        XCTAssertEqual(two.state.tokens(of: .red), [10, 20, -1, -1])
        // A back kick as well as the move forward.
        let black = GameState.progress(of: .black, atTrackIndex: 7)
        let kick = session(versus(.novice), red: [12, -1, -1, -1], black: [black, -1, -1, -1], dice: [5])
        await kick.roll()
        XCTAssertEqual(kick.state.tokens(of: .red)[0], 12)
        XCTAssertEqual(Set(kick.choices(for: 0).map(\.kind)), [.forward, .backKick])
    }

    func testNotBringingATokenOut() async {
        let s = session(versus(.novice), red: [-1, -1, -1, -1], dice: [6])
        await s.roll()
        XCTAssertEqual(s.state.tokens(of: .red), [-1, -1, -1, -1], "coming out is yours to tap")
    }
}
