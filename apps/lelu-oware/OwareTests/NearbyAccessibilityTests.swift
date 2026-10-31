import MatchKit
import OwareEngine
import XCTest
@testable import Oware

/// What VoiceOver hears in a nearby game when the other phone drops, comes back or goes: the
/// banners appear without a sound, so each one is also spoken.
@MainActor
final class NearbyAccessibilityTests: XCTestCase {
    private func spoken(_ event: RoomEvent<OwareTable>, mySeat: Int = 0, gameOver: Bool = false) -> String? {
        GameSession.connectionAnnouncement(for: event, mySeat: mySeat, opponentName: "Ama", gameOver: gameOver)
    }

    func testTheOtherPhoneDroppingAndComingBackIsSpoken() {
        XCTAssertEqual(spoken(.reconnecting(seat: 1)), "Reconnecting to Ama.")
        XCTAssertEqual(spoken(.back(seat: 1)), "Ama is back.")
    }

    func testTheOtherPhoneGoingSaysWhatCanBeDone() {
        XCTAssertEqual(spoken(.seatLost(seat: 1)), "Ama's phone has gone. Play the computer, or leave.")
        XCTAssertEqual(spoken(.left(seat: 1)), "Ama left the game. Play the computer, or leave.")
    }

    /// After the last move there is nothing to carry on: just who went.
    func testAfterTheGameOnlyWhoWentIsSpoken() {
        XCTAssertEqual(spoken(.left(seat: 1), gameOver: true), "Ama left the game.")
    }

    /// The guest hears about the host's phone (seat 0), never about its own seat.
    func testOnlyTheOtherPhoneIsSpokenOf() {
        XCTAssertNil(spoken(.reconnecting(seat: 0), mySeat: 0))
        XCTAssertEqual(spoken(.reconnecting(seat: 0), mySeat: 1), "Reconnecting to Ama.")
        XCTAssertNil(spoken(.joinRequest(PeerID("x"), name: "Ama")))
    }

    /// A game found nearby reads as one button, without a dangling comma when there is no note.
    func testAGameCardReadsAsOneSentence() {
        XCTAssertEqual(NearbyView.joinLabel(name: "Ama's game", note: "Abapa · Ama starts"), "Join Ama's game, Abapa · Ama starts")
        XCTAssertEqual(NearbyView.joinLabel(name: "Ama's game", note: ""), "Join Ama's game")
    }

    /// A player on the Ready screen says their side's colour, not only shows it.
    func testAPlayerTileSaysTheSide() {
        XCTAssertEqual(NearbyView.tileLabel(name: "Kofi", side: .south, status: "Ready", isMe: true), "You, Kofi, gold side, Ready")
        XCTAssertEqual(NearbyView.tileLabel(name: "Ama", side: .north, status: "Connected", isMe: false), "Ama, red side, Connected")
    }
}
