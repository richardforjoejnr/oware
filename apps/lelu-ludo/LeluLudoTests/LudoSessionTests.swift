import LudoAI
import LudoEngine
import XCTest
@testable import LeluLudo

/// The game as the app plays it: seats, dice, computer turns, saves.
@MainActor
final class LudoSessionTests: XCTestCase {
    private let youVsComputer = GameSetup(seats: [.red: .human, .black: .computer(.intermediate)])

    func testA6LetsYouBringATokenOutAndRollAgain() async throws {
        let session = TestSupport.session(dice: [6, 4])
        session.newGame(youVsComputer)
        XCTAssertTrue(session.canRoll)
        await session.roll()
        XCTAssertEqual(session.state.pendingRoll, 6)
        XCTAssertEqual(Set(session.movableTokens), [0, 1, 2, 3])
        await session.play(token: 0)
        XCTAssertEqual(session.state.tokens(of: .red)[0], 0)
        XCTAssertTrue(session.canRoll, "a 6 rolls again")
        await session.roll()
        await session.play(token: 0)
        XCTAssertEqual(session.state.tokens(of: .red)[0], 4)
    }

    func testWithNothingToMoveTheComputerPlaysAndItIsYourTurnAgain() async {
        // You roll a 3 (nothing out yet: passed); the computer rolls a 2 (passed too); back to you.
        let session = TestSupport.session(dice: [3, 2, 5])
        session.newGame(youVsComputer)
        await session.roll()
        XCTAssertEqual(session.state.toMove, .red, "the computer has had its turn")
        XCTAssertTrue(session.canRoll)
        XCTAssertEqual(session.lastRoll?.color, .black)
    }

    func testTheComputerBringsATokenOutOnASix() async {
        let session = TestSupport.session(dice: [1, 6, 2, 4])
        session.newGame(youVsComputer)
        await session.roll()   // you: 1, pass. Computer: 6 (out), 2 (moves it).
        XCTAssertEqual(session.state.tokens(of: .black).filter { $0 >= 0 }.count, 1)
        XCTAssertEqual(session.state.toMove, .red)
    }

    func testPassAndPlayNeverMovesForAnyone() async {
        let session = TestSupport.session(dice: [3, 6])
        session.newGame(GameSetup(seats: [.red: .human, .yellow: .human]))
        await session.roll()
        XCTAssertEqual(session.state.toMove, .yellow)
        XCTAssertTrue(session.canRoll, "yellow rolls for themselves")
        await session.roll()
        XCTAssertEqual(session.state.pendingRoll, 6, "and chooses for themselves")
    }

    func testOnlyLegalTokensCanBePlayed() async {
        let session = TestSupport.session(dice: [6])
        session.newGame(youVsComputer)
        await session.roll()
        await session.play(token: 9)
        XCTAssertEqual(session.state.pendingRoll, 6, "nothing happened")
    }

    func testAGameResumesAfterRelaunch() async {
        let store = TestSupport.store()
        let session = TestSupport.session(dice: [6, 5], store: store)
        session.newGame(youVsComputer)
        await session.roll()
        await session.play(token: 2)
        let resumed = TestSupport.session(dice: [1], store: store)
        XCTAssertEqual(resumed.state, session.state)
        XCTAssertEqual(resumed.setup, youVsComputer)
        XCTAssertTrue(resumed.hasGame)
    }

    func testComputersAloneFinishAGame() async {
        var dice: [Int] = []
        var rng = SeededGenerator(seed: 5)
        for _ in 0..<4000 { dice.append(Int.random(in: 1...6, using: &rng)) }
        let session = TestSupport.session(dice: dice)
        session.newGame(GameSetup(seats: [.red: .computer(.novice), .yellow: .computer(.grandmaster), .green: .computer(.strategist)]))
        await session.runComputerTurns()
        XCTAssertNotNil(session.state.winner)
        XCTAssertFalse(session.canRoll)
    }

    func testScriptedDiceComeFromTheLaunchFlag() {
        XCTAssertEqual(ScriptedDice.parse("--dice=6,4,3"), [6, 4, 3])
        XCTAssertNil(ScriptedDice.parse("--dice=6,9"), "faces are 1…6")
        XCTAssertNil(ScriptedDice.parse("--other"))
    }
}

/// The die's sixth face is the black star, but it is announced as a number.
@MainActor
final class DiceFaceTests: XCTestCase {
    func testEveryFaceIsSpokenAsANumber() {
        XCTAssertEqual((1...6).map(Pips.spoken), ["one", "two", "three", "four", "five", "six"])
    }
}
