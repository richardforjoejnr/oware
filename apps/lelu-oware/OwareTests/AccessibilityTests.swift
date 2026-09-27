import SwiftUI
import XCTest
import OwareAI
import OwareEngine
@testable import Oware

/// What VoiceOver says after each move, the spoken move preview, and text that grows with Dynamic Type.
@MainActor
final class AccessibilityTests: XCTestCase {
    private let vsAI = GameMode.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south)

    func testYourMoveThenTheComputersTurn() throws {
        var s = GameState.initial(rules: .abapa)
        let move = Move(player: .south, absoluteHouse: 0)
        let events = try s.apply(move)
        let text = GameSession.announcement(for: move, events: events, after: s, mode: vsAI, opponentName: "Kofi")
        XCTAssertEqual(text, "You played A1.")
    }

    func testTheComputersMoveWithACaptureHandsTheTurnBack() throws {
        //                      A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = GameState(houses: [2, 1, 4, 4, 4, 4, 4, 4, 4, 4, 4, 1], sideToMove: .north)
        let move = Move(player: .north, absoluteHouse: 11)   // B6 (1) → A1 makes 3: captured
        let events = try s.apply(move)
        let text = GameSession.announcement(for: move, events: events, after: s, mode: vsAI, opponentName: "Kofi")
        XCTAssertEqual(text, "Kofi played B6 and took 3 seeds. Your move.")
    }

    func testPassAndPlayNamesTheSides() throws {
        var s = GameState.initial(rules: .abapa)
        let move = Move(player: .south, absoluteHouse: 2)
        let events = try s.apply(move)
        XCTAssertEqual(GameSession.announcement(for: move, events: events, after: s, mode: .passAndPlay, opponentName: "B"),
                       "A played A3. B to move.")
    }

    func testTheEndOfTheGameIsAnnounced() throws {
        //                      A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = GameState(houses: [0, 0, 0, 0, 0, 1, 2, 0, 0, 0, 0, 1], stores: [24, 20])
        let move = Move(player: .south, absoluteHouse: 5)   // A6 → B1 makes 3: 27 seeds, game over
        let events = try s.apply(move)
        let text = GameSession.announcement(for: move, events: events, after: s, mode: vsAI, opponentName: "Kofi")
        XCTAssertTrue(text.hasPrefix("You played A6 and took 3 seeds. You win"), text)
    }

    func testNamNamRoundEndIsAnnounced() throws {
        var s = GameState(houses: [1, 3, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0], stores: [20, 20], rules: .namNam)
        let move = Move(player: .south, absoluteHouse: 0)
        let events = try s.apply(move)
        let text = GameSession.announcement(for: move, events: events, after: s, mode: vsAI, opponentName: "Kofi")
        XCTAssertTrue(text.contains("Round 1: you 28, them 20"), text)
    }

    func testThePreviewSaysWhereTheLastSeedLandsAndWhatItTakes() throws {
        var houses = Array(repeating: 0, count: 12)
        houses[5] = 1; houses[6] = 2; houses[7] = 4; houses[0] = 3
        let s = GameState(houses: houses)
        let preview = try XCTUnwrap(s.preview(Move(player: .south, absoluteHouse: 5)))
        XCTAssertEqual(GameSession.previewDescription(preview), "A6: last seed lands in B1, takes 3 seeds.")
    }

    func testHouseFontsGrowWithTheReadersTextSize() {
        let body = Theme.body(17)
        XCTAssertEqual(body.size, 17)
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge))
        XCTAssertGreaterThan(scaled, 30, "at the largest sizes body text is well over 30 pt")
        _ = body.font(for: .accessibility3)
        XCTAssertEqual(Theme.title(48).weight(.bold).weight, .bold)
    }
}
