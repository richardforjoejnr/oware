import XCTest
import OwareEngine
@testable import Oware

/// The lesson must be followable on a phone held either way: it names houses (shown on the board)
/// and points at the glowing one, instead of saying "bottom row" or "to the right".
final class LessonClarityTests: XCTestCase {
    private let lessons: [RuleSet.Variant] = [.abapa, .namNam]

    func testEveryStepThatNeedsATapPointsAtTheGlowingHouse() {
        for variant in lessons {
            for step in Tutorial.steps(for: variant) {
                guard let move = step.requiredMove else { continue }
                XCTAssertTrue(step.prompt.contains("Tap the glowing house, \(move.notation)"), "\(variant) · \(step.title): \(step.prompt)")
            }
        }
    }

    func testNoStepDependsOnHowThePhoneIsHeld() {
        let directions = ["bottom row", "top row", "to the right", "to the left", "clockwise", "anticlockwise"]
        for variant in lessons {
            for step in Tutorial.steps(for: variant) {
                let text = (step.prompt + " " + (step.afterText ?? "")).lowercased()
                for word in directions {
                    XCTAssertFalse(text.contains(word), "\(variant) · \(step.title) says '\(word)'")
                }
            }
        }
    }

    func testTheFirstStepExplainsTheHouseNamesAndCounts() {
        for variant in lessons {
            let first = Tutorial.steps(for: variant)[0].prompt
            XCTAssertTrue(first.contains("A1 to A6") && first.contains("B1 to B6"), "\(variant)")
            XCTAssertTrue(first.contains("how many seeds"), "\(variant): says what the numbers mean")
        }
    }

    func testHouseNamesSitBesideTheirHousesWithoutCoveringTheCounts() {
        for size in [CGSize(width: 390, height: 700), CGSize(width: 844, height: 360)] {
            let layout = BoardLayout(size: size)
            for house in 0..<12 {
                let name = layout.nameLabelPoint(house)
                let count = layout.countLabelPoint(house, withName: true)
                let centre = layout.houseCenter(house)
                XCTAssertGreaterThan(hypot(name.x - count.x, name.y - count.y), layout.houseRadius * 0.5, "\(size) house \(house)")
                XCTAssertLessThan(hypot(name.x - centre.x, name.y - centre.y), layout.houseRadius * 2, "name stays by its house")
                XCTAssertTrue(layout.boardRect.insetBy(dx: -1, dy: -1).contains(name), "\(size) house \(house) name on the board")
            }
        }
    }

    @MainActor
    func testTappingAHouseOnAStepWithNothingToPlaySaysHowToGoOn() {
        let session = GameSession(store: GameStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)))
        session.startTutorial(step: 0, variant: .abapa)   // Welcome: nothing to play
        XCTAssertEqual(session.reasonHouseIsBlocked(0), "Tap Next to carry on")
        session.startTutorial(step: Tutorial.steps.count - 1, variant: .abapa)
        XCTAssertEqual(session.reasonHouseIsBlocked(0), "Tap Play to start a game")
        session.startTutorial(step: 1, variant: .abapa)   // Sowing: A3 is asked for
        XCTAssertEqual(session.reasonHouseIsBlocked(0), "That's A1. Tap the glowing house, A3")
    }
}
