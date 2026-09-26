import XCTest
import SwiftUI
@testable import Oware

final class AdinkraIconsTests: XCTestCase {
    private let box = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testSankofaDrawsInsideItsBox() {
        let path = Adinkra.Sankofa().path(in: box)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(box.insetBy(dx: -2, dy: -2).contains(path.boundingRect), "\(path.boundingRect)")
        XCTAssertGreaterThan(path.boundingRect.width, 70)
        XCTAssertGreaterThan(path.boundingRect.height, 70)
    }

    func testNyansapoIsSymmetricAndInsideItsBox() {
        let path = Adinkra.Nyansapo().path(in: box)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(box.insetBy(dx: -2, dy: -2).contains(path.boundingRect), "\(path.boundingRect)")
        let b = path.boundingRect
        XCTAssertEqual(b.midX, 50, accuracy: 0.5)
        XCTAssertEqual(b.midY, 50, accuracy: 0.5)
        XCTAssertEqual(b.width, b.height, accuracy: 0.5)
    }

    func testGlyphsScaleWithTheirRect() {
        let small = Adinkra.Nyansapo().path(in: CGRect(x: 10, y: 10, width: 20, height: 20)).boundingRect
        XCTAssertTrue(CGRect(x: 8, y: 8, width: 24, height: 24).contains(small), "\(small)")
    }
}
