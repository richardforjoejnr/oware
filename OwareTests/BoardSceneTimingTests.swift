import XCTest
import SpriteKit
import OwareEngine
@testable import Oware

/// The sowing must be *seen*: at normal speed a four-seed move takes well over a second, with
/// the seeds carried from house to house rather than appearing in place.
@MainActor
final class BoardSceneTimingTests: XCTestCase {
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

    func testFourSeedSowingTakesRealTime() async throws {
        guard let (view, scene) = presentedScene() else { throw XCTSkip("needs the app's window") }
        defer { view.removeFromSuperview() }
        let before = GameState.initial
        let result = try before.applying(Move(player: .south, house: 0))
        let clock = ContinuousClock()
        let start = clock.now
        await scene.animate(events: result.events, from: before, to: result.state)
        let elapsed = clock.now - start
        XCTAssertGreaterThan(elapsed, .milliseconds(1000), "seeds should be carried and dropped one at a time")
        XCTAssertLessThan(elapsed, .seconds(4), "but a short move must not drag")
    }

    func testInstantSpeedSkipsTheAnimation() async throws {
        guard let (view, scene) = presentedScene() else { throw XCTSkip("needs the app's window") }
        defer { view.removeFromSuperview() }
        scene.animationSpeed = 100
        let before = GameState.initial
        let result = try before.applying(Move(player: .south, house: 0))
        let clock = ContinuousClock()
        let start = clock.now
        await scene.animate(events: result.events, from: before, to: result.state)
        XCTAssertLessThan(clock.now - start, .milliseconds(200))
    }
}
