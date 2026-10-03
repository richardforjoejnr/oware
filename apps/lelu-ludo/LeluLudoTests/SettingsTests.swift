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
        s.computerPause = .zero
        s.stepPause = .zero
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
