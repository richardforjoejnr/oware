import Foundation
import Observation
import UserNotifications

/// The parts of the notification centre the reminder uses, so tests can stand in for it.
protocol ReminderScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func schedule(id: String, title: String, body: String, at date: DateComponents) async
    func cancel(id: String)
}

struct SystemReminderScheduling: ReminderScheduling {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(id: String, title: String, body: String, at date: DateComponents) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}

/// An opt-in morning note when today's riddle is ready: off unless the player turns it on (in
/// Settings, or from a one-time offer after they have solved daily riddles on two different days).
/// One local notification at a time, rescheduled whenever the app opens or the daily riddle is
/// solved: it skips a day already done, and goes quiet if the player stops coming back. Nothing
/// leaves the device.
@MainActor
@Observable
final class RiddleReminder {
    static let hour = 9
    static let id = "daily-riddle"

    private(set) var isOn: Bool
    /// The player said no to notifications in iOS; Settings explains where to change it.
    private(set) var denied = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let scheduler: ReminderScheduling
    @ObservationIgnored private let testMode: Bool

    init(defaults: UserDefaults = .standard, scheduler: ReminderScheduling = SystemReminderScheduling(),
         testMode: Bool = LaunchOptions.testMode) {
        self.defaults = defaults
        self.scheduler = scheduler
        self.testMode = testMode
        isOn = defaults.bool(forKey: "riddleReminder.on")
    }

    /// Distinct days on which the daily riddle was solved (for the offer).
    var dailyDays: Int { defaults.integer(forKey: "riddleReminder.dailyDays") }

    /// The one-time offer under a solved daily riddle.
    var shouldOffer: Bool { !isOn && !testMode && dailyDays >= 2 && !defaults.bool(forKey: "riddleReminder.offered") }

    func offerShown() { defaults.set(true, forKey: "riddleReminder.offered") }

    func dailySolved(day: Int) {
        guard defaults.object(forKey: "riddleReminder.lastDay") as? Int != day else { return }
        defaults.set(day, forKey: "riddleReminder.lastDay")
        defaults.set(dailyDays + 1, forKey: "riddleReminder.dailyDays")
    }

    /// Asks iOS for permission (its own alert), then schedules the next note.
    func turnOn(solvedToday: Bool, streak: Int, now: Date = .now) async {
        guard !testMode else { return }
        let allowed = await scheduler.requestAuthorization()
        denied = !allowed
        setOn(allowed)
        if allowed { await reschedule(solvedToday: solvedToday, streak: streak, now: now) }
    }

    func turnOff() {
        setOn(false)
        scheduler.cancel(id: Self.id)
    }

    /// Replaces the pending note with the next one.
    func reschedule(solvedToday: Bool, streak: Int, now: Date = .now, calendar: Calendar = .current) async {
        scheduler.cancel(id: Self.id)
        guard isOn, !testMode else { return }
        let when = Self.nextReminder(after: now, solvedToday: solvedToday, calendar: calendar)
        let body = streak > 0 ? "Keep your \(streak)-day streak going." : "One position, one right answer."
        await scheduler.schedule(id: Self.id, title: "Today's riddle is ready", body: body, at: when)
    }

    /// 9 am today if that is still ahead and today's riddle is not done; otherwise 9 am tomorrow.
    static func nextReminder(after now: Date, solvedToday: Bool, calendar: Calendar = .current) -> DateComponents {
        let todayAtNine = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        let date = !solvedToday && todayAtNine > now
            ? todayAtNine
            : calendar.date(byAdding: .day, value: 1, to: todayAtNine) ?? todayAtNine
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: "riddleReminder.on")
    }
}
