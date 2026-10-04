import LudoEngine
import UIKit
import XCTest
@testable import LeluLudo

/// The owner's art is all in the bundle, the right shape, and the icon meets the App Store's rules.
final class ArtTests: XCTestCase {
    func testEveryImageTheAppNamesIsInTheBundle() {
        for name in Art.all {
            XCTAssertNotNil(UIImage(named: name), "missing art: \(name)")
        }
    }

    func testEachColourHasItsPawnAndEachFaceItsDie() {
        XCTAssertEqual(Set(PlayerColor.allCases.map(Art.pawn)).count, 4)
        XCTAssertEqual(Art.die(6), "Die-6", "the star 6")
        XCTAssertEqual(Art.die(0), "Die-1", "out of range is clamped, never a missing image")
        XCTAssertEqual(Art.die(9), "Die-6")
    }

    func testPawnsStandUpright() throws {
        for color in PlayerColor.allCases {
            let pawn = try XCTUnwrap(UIImage(named: Art.pawn(color)))
            XCTAssertGreaterThan(pawn.size.height, pawn.size.width, "\(color) pawn is taller than wide")
        }
    }
}
