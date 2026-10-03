import XCTest
@testable import Oware

/// The full opening once a day; after that a short one, so returning players reach the board fast.
@MainActor
final class SplashScheduleTests: XCTestCase {
    func testFullOnTheFirstLaunchOfTheDayThenShort() {
        let defaults = TestSupport.defaults()
        let calendar = Calendar(identifier: .gregorian)
        let morning = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(SplashSchedule.durationForThisLaunch(defaults: defaults, now: morning, calendar: calendar), SplashSchedule.full)
        let later = morning.addingTimeInterval(3 * 3600)
        XCTAssertEqual(SplashSchedule.durationForThisLaunch(defaults: defaults, now: later, calendar: calendar), SplashSchedule.short)
        let tomorrow = morning.addingTimeInterval(26 * 3600)
        XCTAssertEqual(SplashSchedule.durationForThisLaunch(defaults: defaults, now: tomorrow, calendar: calendar), SplashSchedule.full)
    }

    func testTheShortOpeningIsWellInsideThreeSeconds() {
        XCTAssertLessThanOrEqual(SplashSchedule.short, .seconds(1))
    }
}
