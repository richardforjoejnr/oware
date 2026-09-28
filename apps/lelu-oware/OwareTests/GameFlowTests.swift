import XCTest
import SpriteKit
import OwareAI
import OwareEngine
@testable import Oware

/// The game keeps going whatever the player does mid-move: leaving for Home, starting again,
/// undoing against the computer, or letting it finish the game off-screen.
@MainActor
final class GameFlowTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
    private func session(_ store: GameStore? = nil) -> GameSession {
        let s = GameSession(store: store ?? GameStore(directory: directory()))
        s.minimumThinkTime = .zero
        s.events = PlayerEvents(track: { _ in }, services: nil, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return s
    }
    private let vsAI = GameMode.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south)

    private func waitUntil(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while !condition() {
            if clock.now > end { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func presentedScene() -> (SKView, BoardScene)? {
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 780))
        window.addSubview(view)
        let scene = BoardScene()
        scene.sound = nil
        scene.haptics = nil
        scene.animationSpeed = 1
        view.presentScene(scene)
        return (view, scene)
    }

    // MARK: - Undo against the computer

    func testUndoAgainstTheComputerTakesBackItsReplyAndYourMove() async {
        let s = session()
        s.newGame(vsAI, rules: .abapa)
        s.play(house: 2)
        let replied = await waitUntil { s.humanToMove && s.history.count == 2 }
        XCTAssertTrue(replied, "the computer should have replied")
        s.undo()
        XCTAssertEqual(s.state, .initial(rules: .abapa))
        XCTAssertTrue(s.history.isEmpty)
        XCTAssertTrue(s.humanToMove)
    }

    /// Nam-Nam: the computer can move twice running (it opens the next round). Undo must go back
    /// past both of its moves to your own turn, not stop on one where it is to move.
    func testUndoSkipsEveryComputerMoveInARow() throws {
        let start = GameState.initial(rules: .abapa)
        let north = try start.applying(Move(player: .south, house: 0)).state
        let backToSouth = try north.applying(Move(player: .north, house: 0)).state
        XCTAssertEqual(north.sideToMove, .north)
        XCTAssertEqual(backToSouth.sideToMove, .south)
        let store = GameStore(directory: directory())
        store.save(SavedGame(state: backToSouth, mode: vsAI, history: [start, north, north]))
        let s = session(store)
        XCTAssertEqual(s.history.count, 3)
        s.undo()
        XCTAssertEqual(s.state, start, "back to your own turn")
        XCTAssertTrue(s.history.isEmpty)
        XCTAssertTrue(s.humanToMove)
    }

    func testUndoToAPositionWhereTheComputerOpensLetsItMoveAgain() async throws {
        let computerOpens = GameMode.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .north)
        let start = GameState.initial(rules: .abapa)
        let afterAI = try start.applying(Move(player: .south, house: 0)).state
        let store = GameStore(directory: directory())
        store.save(SavedGame(state: afterAI, mode: computerOpens, history: [start]))
        let s = session(store)
        s.undo()
        XCTAssertTrue(s.isThinking, "the computer is to move and should be asked again")
        let moved = await waitUntil { s.humanToMove }
        XCTAssertTrue(moved)
        XCTAssertEqual(s.history.count, 1)
    }

    // MARK: - Animations that never finish

    /// Leaving the game mid-sowing detaches the board and its actions stop. The move must still
    /// end, or the session would stay "animating" for ever: no taps, no undo, no reply.
    func testLeavingTheBoardMidMoveEndsTheAnimation() async throws {
        guard let (view, scene) = presentedScene() else { throw XCTSkip("needs the app's window") }
        defer { view.removeFromSuperview() }
        let s = session()
        s.newGame(.passAndPlay, rules: .abapa)
        s.attach(scene)
        s.play(house: 0)
        let started = await waitUntil { s.isAnimating }
        XCTAssertTrue(started)
        view.presentScene(nil)   // what leaving the screen does to the scene
        let finished = await waitUntil(.seconds(2)) { !s.isAnimating }
        XCTAssertTrue(finished, "the move must end when the board goes away")
        XCTAssertTrue(s.humanToMove, "and the next player can move")
    }

    /// A new game started mid-move (Play again, Next riddle) replaces the position; the old
    /// move's last frame must not paint over it, nor clear the new game's flags.
    func testNewGameMidMoveIsNotOverwrittenByTheOldAnimation() async throws {
        guard let (view, scene) = presentedScene() else { throw XCTSkip("needs the app's window") }
        defer { view.removeFromSuperview() }
        let s = session()
        s.newGame(.passAndPlay, rules: .abapa)
        s.attach(scene)
        s.play(house: 0)
        let started = await waitUntil { s.isAnimating }
        XCTAssertTrue(started)
        s.newGame(.passAndPlay, rules: .abapa)
        XCTAssertFalse(s.isAnimating)
        s.play(house: 5)
        let second = await waitUntil { s.isAnimating }
        XCTAssertTrue(second, "the new game accepts a move at once")
        let settled = await waitUntil { !s.isAnimating }
        XCTAssertTrue(settled)
        XCTAssertEqual(s.state.houses[0], 4, "the abandoned move left no trace")
        XCTAssertEqual(s.state.houses[5], 0)
    }

    // MARK: - Results

    func testAResultIsRecordedOnceEvenWithoutAScreen() async {
        var finished = 0
        let s = session()
        let journey = JourneyProgress(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        s.journey = journey
        s.events = PlayerEvents(track: { if case .gameFinished = $0 { finished += 1 } }, services: nil,
                                defaults: UserDefaults(suiteName: UUID().uuidString)!)
        s.newGame(.journey(chapter: 0, opponent: 0), rules: .abapa)
        s.play(house: 2)
        let replied = await waitUntil { s.humanToMove && s.history.count == 2 }
        XCTAssertTrue(replied)
        s.resign(.north)   // the computer gives up: you win
        XCTAssertEqual(finished, 1)
        XCTAssertGreaterThan(journey.totalStars, 0, "Journey stars counted with no game screen open")

        // Undoing past the end and finishing again is the same game.
        s.undo()
        XCTAssertFalse(s.isGameOver)
        s.resign(.north)
        XCTAssertEqual(finished, 1)

        s.newGame(.passAndPlay, rules: .abapa)
        s.resign(.south)
        XCTAssertEqual(finished, 2, "a new game counts again")
    }

    // MARK: - End sounds

    func testLosingToTheComputerSoundsLikeALoss() {
        XCTAssertEqual(BoardScene.endSound(for: .win(.north, .reachedWinningSeeds), humanSide: .south).sound, .lose)
        XCTAssertEqual(BoardScene.endSound(for: .win(.south, .reachedWinningSeeds), humanSide: .south).sound, .win)
        XCTAssertEqual(BoardScene.endSound(for: .win(.north, .reachedWinningSeeds), humanSide: nil).sound, .win,
                       "two players at one board: someone won")
        let draw = BoardScene.endSound(for: .draw(.repetition), humanSide: .south)
        XCTAssertEqual(draw.sound, .win)
        XCTAssertLessThan(draw.volume, 1)
    }
}
