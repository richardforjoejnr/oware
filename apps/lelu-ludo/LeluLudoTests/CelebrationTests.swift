import LudoEngine
import XCTest
@testable import LeluLudo

/// The moments the game celebrates: one of your tokens home mid-game, your win, your loss.
@MainActor
final class CelebrationTests: XCTestCase {
    func testYourTokenReachingHomeIsCheered() async {
        let s = TestSupport.session(dice: [3, 1])
        s.load(.homeNext)
        await s.roll()   // the 3 brings the token on the second square before home in (the only move)
        XCTAssertEqual(s.state.tokens(of: .red)[2], Board.home)
        XCTAssertEqual(s.homeCheer?.color, .red)
        XCTAssertEqual(s.homeCheer?.token, 2)
        XCTAssertEqual(s.homeCheer?.spoken, "Eiii! Chale! Your token is home.")
        XCTAssertNil(s.outcome, "the game goes on")
    }

    /// Once per token: the next throw (yours or anyone's) ends the cheer, so later moves never
    /// bring it back.
    func testTheCheerIsOverAtTheNextThrow() async {
        let s = TestSupport.session(dice: [3, 1, 2, 4])
        s.load(.homeNext)
        await s.roll()
        XCTAssertNotNil(s.homeCheer)
        XCTAssertTrue(s.canRoll, "home earns another roll")
        await s.roll()
        XCTAssertNil(s.homeCheer, "not again on the next turn")
    }

    /// Friends sharing the phone (2, 3 or 4): each one's token home is cheered, named by colour.
    func testEachFriendsTokenHomeIsCheered() async {
        for players in 2...4 {
            let colors = Array([PlayerColor.red, .yellow, .black, .green].prefix(players))
            let mover = colors.last!
            var tokens = Dictionary(uniqueKeysWithValues: colors.map { ($0, [-1, -1, -1, -1]) })
            tokens[mover] = [Board.home - 3, -1, -1, -1]
            let state = GameState.arranged(players: colors, toMove: mover, tokens: tokens)
            let store = TestSupport.store()
            store.save(SavedGame(setup: GameSetup(seats: Dictionary(uniqueKeysWithValues: colors.map { ($0, Seat.human) })),
                                 state: state, aiSeed: 1))
            let s = TestSupport.session(dice: [3], store: store)
            await s.roll()
            await s.tap(token: 0)   // with friends nothing moves by itself: the player taps their token
            XCTAssertEqual(s.homeCheer?.color, mover, "\(players) players")
            XCTAssertEqual(s.homeCheer?.spoken, "Eiii! Chale! \(mover.name)'s token is home.", "\(players) players")
        }
    }

    func testAComputersTokenHomeIsNotCheered() async {
        // Black (a computer) brings a token in mid-game with a 3.
        let state = GameState.arranged(players: [.red, .black], toMove: .black,
                                       tokens: [.red: [-1, -1, -1, -1], .black: [Board.home, Board.home, Board.home - 3, -1]])
        let store = TestSupport.store()
        store.save(SavedGame(setup: GameSetup(seats: [.red: .human, .black: .computer(.novice)]), state: state, aiSeed: 1))
        let s = TestSupport.session(dice: [3, 1], store: store)
        await s.runComputerTurns()
        XCTAssertEqual(s.state.tokens(of: .black)[2], Board.home, "the computer brought its token in")
        XCTAssertNil(s.homeCheer, "the cheer is for your tokens")
    }

    func testYourWinIsTheWinCardNotACheer() async throws {
        let s = TestSupport.session(dice: [3])
        s.load(.winNext)
        await s.roll()
        let outcome = try XCTUnwrap(s.outcome)
        XCTAssertTrue(outcome.youWon)
        XCTAssertEqual(outcome.winner, .red)
        XCTAssertEqual(outcome.phrase, "Wadi nkunim!")
        XCTAssertEqual(outcome.meaning, "You win!")
        XCTAssertNil(s.homeCheer, "the last token home is the win itself, not a cheer")
    }

    func testTheComputersWinIsYourLoss() async throws {
        let s = TestSupport.session(dice: [3])
        s.load(.loseNext)
        await s.runComputerTurns()
        let outcome = try XCTUnwrap(s.outcome)
        XCTAssertFalse(outcome.youWon)
        XCTAssertEqual(outcome.winner, .black)
        XCTAssertEqual(outcome.yours, .red, "your pawn is the one knocked over")
        XCTAssertEqual(outcome.phrase, "Wa ri, wa ri!")
        XCTAssertEqual(outcome.meaning, "You've lost. Black wins.")
    }

    func testWithFriendsTheWinnerIsNamedByColour() {
        let outcome = Outcome(winner: .yellow, winnerName: "Yellow", youWon: true, yours: nil)
        XCTAssertEqual(outcome.meaning, "Yellow wins!")
    }

    func testANewGameClearsTheCheerAndTheOutcome() async {
        let s = TestSupport.session(dice: [3])
        s.load(.winNext)
        await s.roll()
        XCTAssertNotNil(s.outcome)
        s.newGame(s.setup)
        XCTAssertNil(s.outcome, "Play again starts afresh")
        XCTAssertNil(s.homeCheer)
    }

    func testOnlyAPersonsWinPlaysTheFanfare() async {
        let rec = RecordingFeedback()
        let s = LudoSession(store: TestSupport.store(), dice: ScriptedDice([3]), feedback: rec)
        s.pacing = .instant
        s.load(.loseNext)
        await s.runComputerTurns()
        XCTAssertNotNil(s.outcome)
        XCTAssertFalse(rec.played.contains(.win), "no fanfare when the computer wins")
    }
}
