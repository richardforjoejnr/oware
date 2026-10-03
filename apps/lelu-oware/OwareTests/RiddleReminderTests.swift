import XCTest
@testable import Oware

/// The opt-in morning note: offered once, asks iOS only when turned on, one note at a time.
@MainActor
final class RiddleReminderTests: XCTestCase {
    final class FakeScheduler: ReminderScheduling, @unchecked Sendable {
        var allow = true
        var asked = 0
        var scheduled: [(title: String, body: String, at: DateComponents)] = []
        var cancelled = 0
        func requestAuthorization() async -> Bool { asked += 1; return allow }
        func schedule(id: String, title: String, body: String, at date: DateComponents) async { scheduled.append((title, body, date)) }
        func cancel(id: String) { cancelled += 1 }
    }

    private let calendar = Calendar(identifier: .gregorian)
    private func date(_ h: Int, day: Int = 5) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: 30))!
    }

    func testOffYetAndOfferedOnlyAfterDailyRiddlesOnTwoDays() {
        let reminder = RiddleReminder(defaults: TestSupport.defaults(), scheduler: FakeScheduler(), testMode: false)
        XCTAssertFalse(reminder.isOn)
        reminder.dailySolved(day: 100)
        reminder.dailySolved(day: 100)
        XCTAssertFalse(reminder.shouldOffer, "one day is not enough")
        reminder.dailySolved(day: 101)
        XCTAssertTrue(reminder.shouldOffer)
        reminder.offerShown()
        XCTAssertFalse(reminder.shouldOffer, "offered once")
    }

    func testTurningOnAsksIOSThenSchedulesOneNote() async {
        let fake = FakeScheduler()
        let reminder = RiddleReminder(defaults: TestSupport.defaults(), scheduler: fake, testMode: false)
        await reminder.turnOn(solvedToday: false, streak: 3, now: date(7))
        XCTAssertEqual(fake.asked, 1)
        XCTAssertTrue(reminder.isOn)
        XCTAssertEqual(fake.scheduled.count, 1)
        XCTAssertEqual(fake.scheduled.first?.body, "Keep your 3-day streak going.")
        reminder.turnOff()
        XCTAssertFalse(reminder.isOn)
        XCTAssertGreaterThan(fake.cancelled, 0, "the pending note is removed")
    }

    func testSayingNoInIOSLeavesItOffAndExplains() async {
        let fake = FakeScheduler()
        fake.allow = false
        let reminder = RiddleReminder(defaults: TestSupport.defaults(), scheduler: fake, testMode: false)
        await reminder.turnOn(solvedToday: false, streak: 0)
        XCTAssertFalse(reminder.isOn)
        XCTAssertTrue(reminder.denied)
        XCTAssertTrue(fake.scheduled.isEmpty)
    }

    func testNineTodayUnlessDoneOrPastThenNineTomorrow() {
        func at(_ c: DateComponents) -> String { "\(c.day!) \(c.hour!):\(c.minute!)" }
        XCTAssertEqual(at(RiddleReminder.nextReminder(after: date(7), solvedToday: false, calendar: calendar)), "5 9:0")
        XCTAssertEqual(at(RiddleReminder.nextReminder(after: date(7), solvedToday: true, calendar: calendar)), "6 9:0")
        XCTAssertEqual(at(RiddleReminder.nextReminder(after: date(14), solvedToday: false, calendar: calendar)), "6 9:0")
    }

    func testTestLaunchesNeverAskOrSchedule() async {
        let fake = FakeScheduler()
        let reminder = RiddleReminder(defaults: TestSupport.defaults(), scheduler: fake, testMode: true)
        await reminder.turnOn(solvedToday: false, streak: 0)
        await reminder.reschedule(solvedToday: false, streak: 0)
        XCTAssertEqual(fake.asked, 0)
        XCTAssertTrue(fake.scheduled.isEmpty)
        reminder.dailySolved(day: 1); reminder.dailySolved(day: 2)
        XCTAssertFalse(reminder.shouldOffer)
    }
}
