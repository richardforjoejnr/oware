import Foundation
import OwareAI
import OwareEngine

/// Turns what happens in the game into analytics signals and Game Center scores. The screens call
/// this; it decides what each moment means (a win against the Grandmaster, a finished chapter).
@MainActor
final class PlayerEvents {
    static let shared = PlayerEvents()

    var track: (AnalyticsEvent) -> Void
    var services: GameServices?
    private let defaults: UserDefaults
    private static let grandmasterWinsKey = "stats.grandmasterWins"

    init(track: @escaping (AnalyticsEvent) -> Void = { Analytics.shared.track($0) },
         services: GameServices? = GameCenter.shared,
         defaults: UserDefaults = .standard) {
        self.track = track
        self.services = services
        self.defaults = defaults
    }

    var grandmasterWins: Int { defaults.integer(forKey: Self.grandmasterWinsKey) }

    func gameFinished(mode: GameMode, state: GameState) {
        guard let outcome = state.outcome else { return }
        let rules = state.rules.variant.rawValue
        let modeName: String
        var level: Difficulty?
        switch mode {
        case let .versusAI(difficulty, _, _): modeName = "computer"; level = difficulty
        case .journey: modeName = "journey"; level = mode.journeyOpponent?.difficulty
        case .passAndPlay: modeName = "passAndPlay"
        case .puzzle, .tutorial: return
        }
        let result: String
        if case .passAndPlay = mode {
            result = outcome.winner.map { $0 == .south ? "A" : "B" } ?? "draw"
        } else {
            let human = mode.aiSide?.opponent ?? .south
            result = outcome.winner == nil ? "draw" : (outcome.winner == human ? "win" : "loss")
        }
        track(.gameFinished(mode: modeName, level: level.map { "\($0)" }, result: result, rules: rules))

        guard result == "win" else { return }
        services?.unlock(GameCenterID.Achievement.firstWin)
        if level == .grandmaster {
            let wins = grandmasterWins + 1
            defaults.set(wins, forKey: Self.grandmasterWinsKey)
            services?.submit(wins, to: GameCenterID.Leaderboard.grandmasterWins)
            services?.unlock(GameCenterID.Achievement.beatGrandmaster)
        }
        if outcome.reason == .territory {
            services?.unlock(GameCenterID.Achievement.allTwelveHouses)
        }
    }

    /// After a Journey result is recorded: the new star total, and any chapter just completed.
    func journeyProgress(totalStars: Int, chapterCompleted: Int?) {
        services?.submit(totalStars, to: GameCenterID.Leaderboard.journeyStars)
        if let chapter = chapterCompleted {
            track(.journeyChapterCompleted(chapter: chapter + 1))
            services?.unlock(GameCenterID.Achievement.firstChapter)
        }
    }

    func riddleSolved(_ puzzle: Puzzle, daily: Bool, streak: Int) {
        track(.riddleSolved(kind: puzzle.kind.rawValue, daily: daily))
        services?.unlock(GameCenterID.Achievement.firstRiddle)
        if daily { services?.submit(streak, to: GameCenterID.Leaderboard.riddleStreak) }
    }

    func lessonCompleted(rules: RuleSet.Variant) {
        track(.lessonCompleted(rules: rules.rawValue))
        services?.unlock(GameCenterID.Achievement.lessonDone)
    }

    func tipJarViewed() { track(.tipJarViewed) }

    func tipPurchased(productID: String?) {
        let tier = productID?.split(separator: ".").last.map(String.init) ?? "unknown"
        track(.tipPurchased(tier: tier))
    }
}
