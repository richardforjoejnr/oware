import Foundation
import Observation

/// When to show Apple's rating prompt: only at a high point, after a finished game, never mid-game
/// (HIG ratings and reviews). A high point is the 3rd, 10th or 25th win, or a finished Journey
/// chapter. At most once per app version and two weeks apart; iOS itself caps it at three a year.
@MainActor
@Observable
final class ReviewMoments {
    static let winMilestones: Set<Int> = [3, 10, 25]
    static let minimumGap: TimeInterval = 14 * 24 * 3600

    /// Set at a high point; the game-over screen takes it and asks.
    private(set) var pending = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let version: String
    @ObservationIgnored private let now: () -> Date

    init(defaults: UserDefaults = .standard,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
         now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.version = version
        self.now = now
    }

    var wins: Int { defaults.integer(forKey: "review.wins") }

    func gameWon() {
        let wins = self.wins + 1
        defaults.set(wins, forKey: "review.wins")
        if Self.winMilestones.contains(wins) { highPoint() }
    }

    func chapterCompleted() { highPoint() }

    /// True once per high point; the caller then shows the prompt and calls `asked()`.
    func takePending() -> Bool {
        guard pending else { return false }
        pending = false
        return true
    }

    /// The prompt was shown: no more this version, and none for two weeks.
    func asked() {
        defaults.set(version, forKey: "review.askedVersion")
        defaults.set(now(), forKey: "review.askedAt")
    }

    private func highPoint() {
        guard defaults.string(forKey: "review.askedVersion") != version else { return }
        if let last = defaults.object(forKey: "review.askedAt") as? Date, now().timeIntervalSince(last) < Self.minimumGap { return }
        pending = true
    }
}
