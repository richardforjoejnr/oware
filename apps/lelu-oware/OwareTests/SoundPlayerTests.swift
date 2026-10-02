import XCTest
@testable import Oware

/// Sound reaches the audio hardware only when a sound plays, never just because a board appears:
/// the audio server can stall, and the board must draw anyway.
@MainActor
final class SoundPlayerTests: XCTestCase {
    func testABoardDoesNotStartTheAudioEngine() {
        _ = BoardScene()
        XCTAssertFalse(SoundPlayer.shared.hasEngine)
    }

    func testNoEngineWhileSoundIsOff() {
        let player = SoundPlayer.shared
        let wasEnabled = player.enabled
        defer { player.enabled = wasEnabled }
        player.enabled = false
        player.play(.tick)
        XCTAssertFalse(player.hasEngine)
    }
}
