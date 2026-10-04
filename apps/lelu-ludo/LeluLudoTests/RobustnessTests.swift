import Foundation
import LudoAI
import LudoEngine
import XCTest
@testable import LeluLudo

/// A fair die from a seed, so long random games replay exactly.
@MainActor
final class SeededDice: DiceSource {
    private var rng: SeededGenerator
    init(seed: UInt64) { rng = SeededGenerator(seed: seed) }
    func roll() -> Int { Int.random(in: 1...6, using: &rng) }
}

/// Crash hunting and recovery: relaunching at any point, damaged saves, stale tasks, long games.
@MainActor
final class RobustnessTests: XCTestCase {
    private let youVsComputer = GameSetup(seats: [.red: .human, .black: .computer(.novice)])

    private func session(saving state: GameState, setup: GameSetup, dice: [Int], store: GameStore? = nil) -> (LudoSession, GameStore) {
        let store = store ?? TestSupport.store()
        store.save(SavedGame(setup: setup, state: state, aiSeed: 1))
        return (TestSupport.session(dice: dice, store: store), store)
    }

    /// Someone can always act: you roll, you choose a token, or the computer is playing.
    private func someoneCanAct(_ s: LudoSession) -> Bool {
        s.state.isOver || s.canRoll || !s.movableTokens.isEmpty || s.isComputerPlaying
    }

    // MARK: Relaunch

    /// Killed while a computer was about to roll (or had rolled): on relaunch the game must carry on.
    /// Nothing calls `runComputerTurns()` except `roll()` and `play(_:)`, both of which need a person's
    /// turn, so the game sits on "Black to roll" for ever.
    func testARelaunchOnAComputersTurnCarriesOn() async throws {
        let state = GameState.arranged(players: [.red, .black], toMove: .black, tokens: [.red: [4, -1, -1, -1]])
        let (s, _) = session(saving: state, setup: youVsComputer, dice: [3, 2])
        XCTAssertTrue(s.hasGame, "offered as Continue")
        try await Task.sleep(for: .milliseconds(100))   // give any resume a chance to start
        XCTAssertTrue(someoneCanAct(s), "stuck: Black to move, nobody plays it (canRoll \(s.canRoll), movable \(s.movableTokens))")
    }

    func testARelaunchAfterTheComputerRolledCarriesOn() async throws {
        var state = GameState.arranged(players: [.red, .black], toMove: .black, tokens: [.black: [4, -1, -1, -1]])
        state.roll(3)   // saved between the computer's roll and its move
        let (s, _) = session(saving: state, setup: youVsComputer, dice: [2])
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(someoneCanAct(s), "stuck: Black rolled 3, nobody plays it")
    }

    /// The same after a lesson: leaving it restores a saved game that may be on a computer's turn.
    func testLeavingALessonOntoAComputersTurnCarriesOn() async throws {
        let state = GameState.arranged(players: [.red, .black], toMove: .black, tokens: [.red: [4, -1, -1, -1]])
        let (s, _) = session(saving: state, setup: youVsComputer, dice: [3])
        s.startTutorial()
        s.endTutorial()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(someoneCanAct(s), "stuck after leaving the lesson")
    }

    // MARK: Damaged and old saves

    private func writeSave(_ json: [String: Any]) throws -> GameStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GameStore(directory: dir)
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: dir.appendingPathComponent("current-game.json"))
        return store
    }

    private func savedJSON(_ state: GameState, setup: GameSetup) throws -> [String: Any] {
        let data = try JSONEncoder().encode(SavedGame(setup: setup, state: state, aiSeed: 7))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A save holding a roll that no token can play (an older engine's rules, or damage) loads, but
    /// then you can neither roll (a roll is pending) nor move (no legal move): stuck for good.
    func testASaveWithAnUnplayableRollIsRefusedOrPlayable() throws {
        var json = try savedJSON(GameState.arranged(players: [.red, .black], toMove: .red, tokens: [:]), setup: youVsComputer)
        var state = try XCTUnwrap(json["state"] as? [String: Any])
        state["pendingRoll"] = 3   // every token in the yard: a 3 has no move
        json["state"] = state
        let s = TestSupport.session(dice: [6], store: try writeSave(json))
        XCTAssertTrue(!s.hasGame || someoneCanAct(s), "loaded a game nobody can play: canRoll \(s.canRoll), movable \(s.movableTokens)")
    }

    /// The same on a computer's turn: `runComputerTurns()` loops for ever (the AI has no move, the roll
    /// stays pending), with the board saying "Black is playing…". With `.instant` pacing (the UI
    /// tests' `--fast`) it is a busy loop on the main actor: the app hangs.
    func testAComputerWithAnUnplayableRollDoesNotLoopForever() async throws {
        var json = try savedJSON(GameState.arranged(players: [.red, .black], toMove: .black, tokens: [:]), setup: youVsComputer)
        var state = try XCTUnwrap(json["state"] as? [String: Any])
        state["pendingRoll"] = 2
        json["state"] = state
        let s = TestSupport.session(dice: [6], store: try writeSave(json))
        s.pacing = .init(computer: .milliseconds(5), step: .zero, roll: .zero)
        let task = Task { await s.runComputerTurns() }
        try await Task.sleep(for: .milliseconds(300))
        let looping = s.isComputerPlaying
        // Clean up: a game with no computer to move ends the loop.
        s.newGame(.passAndPlay(players: 2, rules: .ghanaClassic))
        await task.value
        XCTAssertFalse(looping, "the computer loop never ends on an unplayable pending roll")
    }

    func testATruncatedSaveStartsClean() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GameStore(directory: dir)
        store.save(SavedGame(setup: youVsComputer, state: GameState(players: [.red, .black]), aiSeed: 1))
        let url = dir.appendingPathComponent("current-game.json")
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)
        let s = TestSupport.session(dice: [6], store: store)
        XCTAssertFalse(s.hasGame)
        XCTAssertTrue(s.canRoll || s.state.toMove == .red)
        s.newGame(youVsComputer)
        XCTAssertNotNil(store.load(), "a new game replaces the damaged file")
    }

    func testAnOldFormatSaveStartsClean() throws {
        // Before aiSeed existed, and a seat from a format that never was.
        var json = try savedJSON(GameState(players: [.red, .black]), setup: youVsComputer)
        json["aiSeed"] = nil
        XCTAssertFalse(TestSupport.session(dice: [6], store: try writeSave(json)).hasGame)
        json = try savedJSON(GameState(players: [.red, .black]), setup: youVsComputer)
        json["setup"] = ["seats": ["red", "human"]]
        XCTAssertFalse(TestSupport.session(dice: [6], store: try writeSave(json)).hasGame)
    }

    // MARK: Settings from an older version

    /// Custom rules from older settings (or damaged defaults) are used as they are: entry rolls that
    /// are empty or not die faces make a game nobody can ever start (no token leaves the yard), and
    /// every save of it is then refused on load (GameState checks entry rolls), so it is lost on relaunch.
    func testStoredCustomRulesAlwaysLetATokenOut() throws {
        for bad: Set<Int> in [[], [7]] {
            let d = TestSupport.defaults()
            d.set("custom", forKey: "rulesPreset")
            d.set(try JSONEncoder().encode(RuleSet(entryRolls: bad)), forKey: "customRules")
            let settings = AppSettings(defaults: d, testMode: true)
            XCTAssertFalse(settings.rules.entryRolls.isEmpty, "entry rolls \(bad)")
            XCTAssertTrue(settings.rules.entryRolls.isSubset(of: 1...6), "entry rolls \(bad)")
        }
    }

    func testSettingsFromAnOlderVersionLoad() throws {
        let d = TestSupport.defaults()
        d.set("someOldPreset", forKey: "rulesPreset")
        d.set(Data("not json".utf8), forKey: "customRules")
        d.set(1, forKey: "soundOn")
        d.set("yes", forKey: "hapticsOn")
        let settings = AppSettings(defaults: d, testMode: true)
        XCTAssertEqual(settings.preset, .ghanaClassic)
        XCTAssertEqual(settings.custom, .ghanaClassic)
        XCTAssertTrue(settings.soundOn)
        XCTAssertTrue(settings.hapticsOn)
    }

    // MARK: Finished games and lessons

    func testAFinishedGameIsNeverOfferedAsContinue() async throws {
        let h = Board.home
        let state = GameState.arranged(players: [.red, .black], toMove: .red, tokens: [.red: [h, h, h, h - 3]])
        let (s, store) = session(saving: state, setup: youVsComputer, dice: [3])
        await s.roll()
        await s.tap(token: 3)
        XCTAssertEqual(s.state.winner, .red)
        XCTAssertFalse(s.hasGame)
        XCTAssertNil(store.load())
        XCTAssertFalse(TestSupport.session(dice: [1], store: store).hasGame, "not after relaunch either")
    }

    /// Leaving a lesson while its token is still walking: the walk finishes and plays the lesson's move
    /// on whatever game is loaded by then, which is the player's own saved game, and saves it.
    func testLeavingALessonMidMoveNeverPlaysIntoTheSavedGame() async throws {
        var saved = GameState.arranged(players: [.red, .black], toMove: .red, tokens: [:])
        saved.roll(6)   // you rolled a 6 in your own game, then went to Learn
        let (s, store) = session(saving: saved, setup: youVsComputer, dice: [1])
        s.pacing = .init(computer: .zero, step: .milliseconds(150), roll: .zero)
        s.startTutorial(at: 0)   // "Your yard": roll a 6, bring a token out
        await s.roll()
        let walking = Task { await s.tap(token: 0) }
        while s.motion == nil { await Task.yield() }
        s.endTutorial()          // Home, mid-walk
        await walking.value
        XCTAssertEqual(s.state, saved, "the lesson's move was played in your own game")
        XCTAssertEqual(store.load()?.state, saved, "and saved over it")
    }

    // MARK: Stale tasks

    /// Home while the computer is thinking, then a new game: the old computer loop wakes from its pause
    /// and rolls for whoever is to move in the new game, a person included.
    func testAStaleComputerLoopNeverRollsInTheNextGame() async throws {
        let state = GameState.arranged(players: [.red, .black], toMove: .black, tokens: [.red: [4, -1, -1, -1]])
        let (s, _) = session(saving: state, setup: youVsComputer, dice: [3, 2, 1])
        s.pacing = .init(computer: .milliseconds(150), step: .zero, roll: .zero)
        let old = Task { await s.runComputerTurns() }
        try await Task.sleep(for: .milliseconds(30))   // the computer is pausing before its roll
        s.newGame(youVsComputer)                        // Home, Play
        await old.value
        XCTAssertNil(s.lastRoll, "someone rolled in the new game: \(String(describing: s.lastRoll))")
        XCTAssertEqual(s.state, GameState(players: [.red, .black]), "the new game is untouched")
        XCTAssertTrue(s.canRoll, "it is your first roll")
    }

    /// The same into a lesson: the lesson's scripted die is rolled for you.
    func testAStaleComputerLoopNeverRollsInALesson() async throws {
        let state = GameState.arranged(players: [.red, .black], toMove: .black, tokens: [.red: [4, -1, -1, -1]])
        let (s, _) = session(saving: state, setup: youVsComputer, dice: [3, 2, 1])
        s.pacing = .init(computer: .milliseconds(150), step: .zero, roll: .zero)
        let old = Task { await s.runComputerTurns() }
        try await Task.sleep(for: .milliseconds(30))
        s.endTutorial()
        s.startTutorial(at: 0)
        await old.value
        XCTAssertNil(s.lastRoll, "the lesson's roll was made for you")
        XCTAssertNil(s.state.pendingRoll)
    }

    /// A new game starts with a clean slate: no commentary or chosen token from the last one.
    func testANewGameForgetsTheLastGamesCommentaryAndChoice() async throws {
        let black = GameState.progress(of: .black, atTrackIndex: 7)
        let state = GameState.arranged(players: [.red, .black], toMove: .red, tokens: [.red: [12, -1, -1, -1], .black: [black, -1, -1, -1]])
        let (s, _) = session(saving: state, setup: GameSetup(seats: [.red: .human, .black: .human]), dice: [5, 3])
        await s.roll()
        await s.tap(token: 0)   // forward or back kick: chosen, waiting
        XCTAssertEqual(s.selectedToken, 0)
        await s.play(try XCTUnwrap(s.choices(for: 0).first { $0.kind == .backKick }))
        await s.roll()          // a kick earned a roll: 3
        await s.tap(token: 0)
        s.newGame(youVsComputer)
        XCTAssertEqual(s.log, [], "the old game's commentary shows in the new one")
        XCTAssertNil(s.selectedToken)
    }

    // MARK: Long games

    /// Rule sets to play: both presets, then a spread of Custom switches.
    private static func ruleSets() -> [RuleSet] {
        var sets: [RuleSet] = [.ghanaClassic, .classic]
        var rng = SeededGenerator(seed: 2026)
        for i in 0..<6 {   // a spread, kept short: the engine's own tests cover rule sets in depth
            func flag() -> Bool { Bool.random(using: &rng) }
            sets.append(RuleSet(kickOrHomeEarnsRoll: flag(), threeSixesForfeit: flag(),
                                stacking: RuleSet.Stacking.allCases[i % 3], backKick: flag(),
                                startSquaresSafe: flag(), starSquaresSafe: flag(),
                                entryRolls: i % 2 == 0 ? [6] : [1, 6], homeKick: flag(),
                                forwardSideKick: flag(), backSideKick: flag()))
        }
        // Every kick at once and none at all, with each stacking rule.
        for stacking in RuleSet.Stacking.allCases {
            sets.append(RuleSet(stacking: stacking, startSquaresSafe: true, starSquaresSafe: true))
            sets.append(RuleSet(kickOrHomeEarnsRoll: false, threeSixesForfeit: false, stacking: stacking, backKick: false,
                                homeKick: false, forwardSideKick: false, backSideKick: false))
        }
        return sets
    }

    /// Plays whole games through the session, as a person taps: computers, pass & play and mixed
    /// tables of 2–4, under every rule set above. After every action: someone can act, the save
    /// matches the board, a finished game is cleared, and no move is left half done.
    func testManyGamesAlwaysFinishAndNeverGetStuck() async throws {
        let levels = LudoAIDifficulty.allCases
        var played = 0
        for (r, rules) in Self.ruleSets().enumerated() {
            for players in 2...4 {
                let mode = (r + players) % 3   // 0: all computers, 1: pass & play, 2: you and computers
                let colors = Array([PlayerColor.red, .black, .yellow, .green].prefix(players))
                var seats: [PlayerColor: Seat] = [:]
                for (i, c) in colors.enumerated() {
                    switch mode {
                    case 0: seats[c] = .computer(levels[(r + i) % levels.count])
                    case 1: seats[c] = .human
                    default: seats[c] = i == 0 ? .human : .computer(levels[(r + i) % levels.count])
                    }
                }
                let seed = UInt64(r * 10 + players)
                let store = TestSupport.store()
                let s = LudoSession(store: store, dice: SeededDice(seed: seed))
                s.pacing = .instant
                s.newGame(GameSetup(seats: seats, rules: rules))
                var rng = SeededGenerator(seed: seed &+ 99)
                var actions = 0
                let context = "rules #\(r) \(rules), \(players) players, mode \(mode)"
                while !s.state.isOver {
                    actions += 1
                        guard actions < 5_000 else {
                        XCTFail("no winner after 5000 actions: \(context)\nstate \(s.state)")
                        break
                    }
                    if s.canRoll {
                        await s.roll()
                    } else if let token = s.movableTokens.randomElement(using: &rng) {
                        let moves = s.choices(for: token)
                        XCTAssertFalse(moves.isEmpty, "a movable token with no move: \(context)")
                        guard let move = moves.randomElement(using: &rng) else { break }
                        await s.play(move)
                    } else if case .computer = s.setup.seat(s.state.toMove), !s.isComputerPlaying {
                        await s.runComputerTurns()
                    } else {
                        XCTFail("stuck: nobody can act. \(context) state \(s.state)")
                        break
                    }
                    XCTAssertFalse(s.isComputerPlaying, context)
                    XCTAssertNil(s.motion, context)
                    XCTAssertEqual(s.hasGame, !s.state.isOver, context)
                    if s.state.isOver {
                        XCTAssertNil(store.load(), "a finished game is cleared: \(context)")
                    } else {
                        if actions % 50 == 0 { XCTAssertEqual(store.load()?.state, s.state, "the save matches the board: \(context)") }
                        if s.state.pendingRoll != nil {
                            XCTAssertFalse(s.state.legalMoves().isEmpty, "a pending roll always has a move: \(context)")
                        }
                        if case .human = s.setup.seat(s.state.toMove) {
                            XCTAssertTrue(s.canRoll != !s.movableTokens.isEmpty, "a person either rolls or moves: \(context)")
                        }
                    }
                    for c in PlayerColor.allCases {
                        XCTAssertTrue(s.state.tokens(of: c).allSatisfy { (Board.yard...Board.home).contains($0) }, context)
                    }
                }
                if let w = s.state.winner { XCTAssertEqual(s.state.homeCount(w), 4, context) }
                played += 1
            }
        }
        XCTAssertGreaterThan(played, 35)
    }
}
