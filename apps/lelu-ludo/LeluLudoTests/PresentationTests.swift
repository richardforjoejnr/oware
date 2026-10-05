import LudoEngine
import SwiftUI
import XCTest
@testable import LeluLudo

/// Where tokens are drawn: every token of every colour, in the yard, on the track, in a lane and home,
/// lands inside its own area of the board.
@MainActor
final class BoardLayoutTests: XCTestCase {
    let layout = BoardLayout(size: 300)   // 20 pt squares

    private func area(_ color: PlayerColor) -> CGRect {
        let o = layout.yardOrigin(color)
        return CGRect(x: o.x, y: o.y, width: 6 * layout.cell, height: 6 * layout.cell)
    }

    func testYardTokensSitOnTheirFourSpotsInTheirOwnYard() {
        for color in PlayerColor.allCases {
            let spots = (0..<4).map { layout.position(color, token: $0, progress: Board.yard) }
            XCTAssertEqual(Set(spots.map { "\($0.x),\($0.y)" }).count, 4, "\(color): four different spots")
            XCTAssertTrue(spots.allSatisfy { area(color).contains($0) }, "\(color): inside its yard")
        }
    }

    func testHomeTokensSitInTheCentreOnTheirColoursSide() {
        let centre = CGRect(x: 6 * layout.cell, y: 6 * layout.cell, width: 3 * layout.cell, height: 3 * layout.cell)
        let middle = layout.center(Board.centre)
        for color in PlayerColor.allCases {
            let home = (0..<4).map { layout.position(color, token: $0, progress: Board.home) }
            XCTAssertTrue(home.allSatisfy { centre.contains($0) }, "\(color): inside the centre")
            XCTAssertEqual(Set(home.map { "\($0.x),\($0.y)" }).count, 4, "\(color): side by side, not stacked")
            // Towards the colour's own side: red left, yellow top, black right, green bottom.
            let mean = CGPoint(x: home.map(\.x).reduce(0, +) / 4, y: home.map(\.y).reduce(0, +) / 4)
            switch color {
            case .red: XCTAssertLessThan(mean.x, middle.x)
            case .yellow: XCTAssertLessThan(mean.y, middle.y)
            case .black: XCTAssertGreaterThan(mean.x, middle.x)
            case .green: XCTAssertGreaterThan(mean.y, middle.y)
            }
        }
    }

    func testTrackAndLaneTokensSitOnTheCentreOfTheirSquare() {
        for color in PlayerColor.allCases {
            for progress in 0..<Board.home {
                let cell = Board.cell(color, progress: progress)!
                XCTAssertEqual(layout.position(color, token: 0, progress: progress), layout.center(cell))
            }
        }
        XCTAssertEqual(layout.center(Board.Cell(0, 0)), CGPoint(x: 10, y: 10))
    }
}

/// The roll tumbling on the board: where it lands, and when it is shown at all.
@MainActor
final class RollingDieTests: XCTestCase {
    func testItLandsOnTheMiddleOfTheBoardTheSameWayEachTimeForARoll() {
        for roll in 1...200 {
            let p = RollingDie.landing(for: roll)
            XCTAssertTrue((0.3...0.7).contains(p.x) && (0.3...0.7).contains(p.y), "roll \(roll): \(p)")
            XCTAssertEqual(p, RollingDie.landing(for: roll), "the same spot however often the view redraws")
        }
        XCTAssertNotEqual(RollingDie.landing(for: 1), RollingDie.landing(for: 2), "it varies roll to roll")
    }

    func testNotInTests() {
        XCTAssertFalse(RollingDie.shown, "unit tests are a test run")
    }

    func testItDrawsEveryFace() {
        for value in 1...6 {
            let image = ImageRenderer(content: RollingDie(value: value, landing: CGPoint(x: 0.5, y: 0.5)).frame(width: 300, height: 300)).uiImage
            XCTAssertNotNil(image, "face \(value)")
        }
    }
}

/// The opening card draws, the size of a phone.
@MainActor
final class SplashTests: XCTestCase {
    func testTheSplashDraws() {
        let image = ImageRenderer(content: SplashView(done: {}).frame(width: 393, height: 852)).uiImage
        XCTAssertEqual(image?.size, CGSize(width: 393, height: 852))
    }
}

/// The real sound and haptics player: every sound, with each switch on and off, never fails, and
/// the switches are obeyed (a test launch is silent; these settings are not in test mode).
@MainActor
final class DeviceFeedbackTests: XCTestCase {
    private let all: [Feedback] = [.roll, .step, .kick, .home, .threeSixes, .win]

    func testEverySoundPlaysWithSoundAndHapticsOn() {
        let settings = AppSettings(defaults: TestSupport.defaults(), testMode: false)
        XCTAssertTrue(settings.effectiveSound && settings.effectiveHaptics)
        let player = DeviceFeedback(settings: settings)
        for f in all { player.play(f) }
        for f in all { player.play(f) }   // again, with the audio engine already running
    }

    func testNothingPlaysWithBothOff() {
        let settings = AppSettings(defaults: TestSupport.defaults(), testMode: false)
        settings.soundOn = false
        settings.hapticsOn = false
        XCTAssertFalse(settings.effectiveSound || settings.effectiveHaptics)
        let player = DeviceFeedback(settings: settings)
        for f in all { player.play(f) }
    }

    func testATestLaunchIsSilent() {
        let player = DeviceFeedback(settings: AppSettings(defaults: TestSupport.defaults(), testMode: true))
        for f in all { player.play(f) }
    }
}

/// The labels of a token's moves never cover one another, and stay on the board (the screenshot run
/// found "Side kick" covering "Move 5" on the next square).
@MainActor
final class ChoiceMarkerTests: XCTestCase {
    private func overlap(_ a: CGPoint, _ at: String, _ b: CGPoint, _ bt: String) -> Bool {
        let sa = ChoiceMarker.size(at), sb = ChoiceMarker.size(bt)
        return abs(a.x - b.x) < (sa.width + sb.width) / 2 && abs(a.y - b.y) < (sa.height + sb.height) / 2
    }

    func testNeighbouringLabelsAreSpreadApart() {
        let titles = ["Back kick", "Side kick", "Move 5"]
        let ends = [CGPoint(x: 150, y: 150), CGPoint(x: 170, y: 150), CGPoint(x: 190, y: 150)]   // three squares in a row
        let placed = ChoiceMarker.spread(ends, titles: titles, board: 300)
        for i in 0..<3 { for j in (i + 1)..<3 {
            XCTAssertFalse(overlap(placed[i], titles[i], placed[j], titles[j]), "\(titles[i]) covers \(titles[j])")
        } }
        XCTAssertEqual(placed[0], ends[0], "the first stays on its square")
    }

    func testFarApartLabelsStayOnTheirSquares() {
        let ends = [CGPoint(x: 60, y: 60), CGPoint(x: 220, y: 220)]   // well inside the board: no edge nudge
        XCTAssertEqual(ChoiceMarker.spread(ends, titles: ["Move 4", "Back kick"], board: 300), ends)
    }

    func testLabelsStayOnTheBoardEvenAtItsEdges() {
        let ends = [CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 5), CGPoint(x: 295, y: 295)]
        let titles = ["Back kick", "Move 5", "Home kick"]
        for (p, t) in zip(ChoiceMarker.spread(ends, titles: titles, board: 300), titles) {
            let s = ChoiceMarker.size(t)
            XCTAssertTrue(p.x - s.width / 2 >= 0 && p.x + s.width / 2 <= 300 && p.y - s.height / 2 >= 0 && p.y + s.height / 2 <= 300, "\(t) at \(p)")
        }
    }
}

/// The dice throw (owner's storyboard, 2026-10-04): when it lands, what it shows, and what can skip it.
@MainActor
final class DiceThrowTests: XCTestCase {
    func testTheQuickThrowIsShorterAndEveryThrowLandsBeforeItGoesBack() {
        XCTAssertLessThan(ThrowTiming.quick.total, ThrowTiming.full.total)
        for t in [ThrowTiming.full, .quick] {
            XCTAssertLessThan(t.landsAfter, t.total)
            XCTAssertEqual(t.total, t.landsAfter + t.rest + t.returnTrip, accuracy: 1e-9)
        }
        XCTAssertLessThanOrEqual(ThrowTiming.full.total, 2.0, "a full throw stays under two seconds")
        XCTAssertEqual(ThrowTiming.of(.quick), .quick)
    }

    func testItAlwaysComesToRestShowingTheRoll() {
        for value in 1...6 {
            XCTAssertEqual(RollingDie.face(spin: 1080, value: value), value)
            let tumbling = Set(stride(from: 0.0, to: 1000, by: 90).map { RollingDie.face(spin: $0, value: value) })
            XCTAssertGreaterThan(tumbling.count, 3, "it shows several faces while tumbling")
            XCTAssertTrue(tumbling.allSatisfy { (1...6).contains($0) })
        }
    }

    func testLandingOrSkippingRevealsTheRoll() {
        let flight = DieFlight()
        XCTAssertTrue(flight.inFlight(1))
        flight.land(1)
        XCTAssertFalse(flight.inFlight(1))
        XCTAssertTrue(flight.inFlight(2), "the next throw is in the air")
        flight.skip(2)
        XCTAssertFalse(flight.inFlight(2))
        XCTAssertEqual(flight.skipped, 2)
        flight.land(1)   // a late landing of an older throw changes nothing
        XCTAssertEqual(flight.landed, 2)
    }

    /// One die on screen, never two: the tray's die is gone while it is out being thrown, and back once
    /// it returns to the cup (or the throw is skipped).
    func testTheTraysDieIsHiddenWhileItIsThrown() {
        let flight = DieFlight()
        XCTAssertFalse(flight.thrown(0), "before any roll, the tray shows its die")
        XCTAssertTrue(flight.thrown(1), "rolled: out on the board")
        flight.land(1)
        XCTAssertTrue(flight.thrown(1), "landed, but not back in the cup yet")
        flight.returned(1)
        XCTAssertFalse(flight.thrown(1))
        XCTAssertTrue(flight.thrown(2))
        flight.skip(2)
        XCTAssertFalse(flight.thrown(2), "skipping brings it straight back")
    }

    func testTheThrowSettingIsRememberedAndPacesYourAutoMoves() {
        let d = TestSupport.defaults()
        let settings = AppSettings(defaults: d, testMode: false)
        // "Throw dice on board": on by default; with the device's Reduce Motion on, nothing flies.
        XCTAssertTrue(settings.throwDiceOnBoard)
        XCTAssertEqual(settings.diceThrow(reduceMotion: false), .full)
        XCTAssertEqual(settings.diceThrow(reduceMotion: true), .off)
        settings.throwDiceOnBoard = false
        XCTAssertEqual(settings.diceThrow(reduceMotion: false), .off)
        XCTAssertFalse(AppSettings(defaults: d, testMode: false).throwDiceOnBoard, "remembered")
        XCTAssertEqual(ThrowTiming.of(.off), .still)
        XCTAssertTrue(ThrowTiming.still.isStill)
        XCTAssertEqual(ThrowTiming.still.landsAfter, 0, "no flight: it is there at once")
        XCTAssertLessThan(LudoSession.Pacing.normal(.off).yourRoll, LudoSession.Pacing.normal(.quick).yourRoll)
        XCTAssertLessThan(LudoSession.Pacing.normal(.quick).yourRoll, LudoSession.Pacing.normal(.full).yourRoll)
        XCTAssertGreaterThan(LudoSession.Pacing.normal(.full).yourRoll, ThrowTiming.full.landing, "the token waits for the die to land")
        // ...and for the whole throw, die back in the cup, so a move never starts under a flying die.
        XCTAssertGreaterThanOrEqual(LudoSession.Pacing.normal(.full).yourRoll, .milliseconds(Int(ThrowTiming.full.total * 1000)))
        XCTAssertGreaterThanOrEqual(LudoSession.Pacing.normal.roll, .milliseconds(Int(ThrowTiming.quick.total * 1000)))
        XCTAssertGreaterThan(LudoSession.Pacing.normal.roll, ThrowTiming.quick.landing, "a computer waits for its die too")
    }
}
