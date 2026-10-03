import XCTest
import OwareAI
import OwareEngine
@testable import Oware

@MainActor
private final class SpyServices: GameServices {
    var scores: [(Int, String)] = []
    var achievements: [String] = []
    func submit(_ score: Int, to leaderboard: String) { scores.append((score, leaderboard)) }
    func unlock(_ achievement: String) { achievements.append(achievement) }
}

private struct SpyBackend: AnalyticsBackend {
    let sent: (String, [String: String]) -> Void
    func send(_ name: String, parameters: [String: String]) { sent(name, parameters) }
}

/// What each moment in the game reports to analytics and Game Center.
@MainActor
final class PlayerEventsTests: XCTestCase {
    private var events: [AnalyticsEvent] = []
    private var services = SpyServices()
    private var player: PlayerEvents!

    override func setUp() async throws {
        events = []
        services = SpyServices()
        let defaults = TestSupport.defaults()
        player = PlayerEvents(track: { [unowned self] in self.events.append($0) }, services: services, defaults: defaults)
    }

    private func finished(_ winner: Player?, reason: GameEndReason = .reachedWinningSeeds, rules: RuleSet = .abapa) -> GameState {
        var s = GameState.initial(rules: rules)
        s.outcome = winner.map { .win($0, reason) } ?? .draw(reason)
        return s
    }
    private func vs(_ d: Difficulty) -> GameMode { .versusAI(difficulty: d, personality: .balanced, humanPlays: .south) }

    func testWinAgainstTheGrandmasterCountsAndUnlocks() {
        player.gameFinished(mode: vs(.grandmaster), state: finished(.south))
        player.gameFinished(mode: vs(.grandmaster), state: finished(.south))
        XCTAssertEqual(events.first, .gameFinished(mode: "computer", level: "grandmaster", result: "win", rules: "abapa"))
        XCTAssertEqual(services.scores.map(\.0), [1, 2])
        XCTAssertTrue(services.scores.allSatisfy { $0.1 == GameCenterID.Leaderboard.grandmasterWins })
        XCTAssertTrue(services.achievements.contains(GameCenterID.Achievement.beatGrandmaster))
        XCTAssertTrue(services.achievements.contains(GameCenterID.Achievement.firstWin))
        XCTAssertEqual(player.grandmasterWins, 2)
    }

    func testALossReportsButUnlocksNothing() {
        player.gameFinished(mode: vs(.master), state: finished(.north))
        XCTAssertEqual(events, [.gameFinished(mode: "computer", level: "master", result: "loss", rules: "abapa")])
        XCTAssertTrue(services.achievements.isEmpty && services.scores.isEmpty)
    }

    func testAWinAgainstAnEasierLevelIsNotAGrandmasterWin() {
        player.gameFinished(mode: vs(.player), state: finished(.south))
        XCTAssertEqual(services.achievements, [GameCenterID.Achievement.firstWin])
        XCTAssertTrue(services.scores.isEmpty)
    }

    func testTakingAllTwelveHousesInNamNam() {
        player.gameFinished(mode: vs(.beginner), state: finished(.south, reason: .territory, rules: .namNam))
        XCTAssertEqual(events.first, .gameFinished(mode: "computer", level: "beginner", result: "win", rules: "namNam"))
        XCTAssertTrue(services.achievements.contains(GameCenterID.Achievement.allTwelveHouses))
    }

    func testPassAndPlayReportsWhichSideWonWithoutAchievements() {
        player.gameFinished(mode: .passAndPlay, state: finished(.north))
        player.gameFinished(mode: .passAndPlay, state: finished(nil, reason: .repetition))
        XCTAssertEqual(events, [.gameFinished(mode: "passAndPlay", level: nil, result: "B", rules: "abapa"),
                                .gameFinished(mode: "passAndPlay", level: nil, result: "draw", rules: "abapa")])
        XCTAssertTrue(services.achievements.isEmpty)
    }

    func testRiddlesAndLessonsAreNotGames() {
        player.gameFinished(mode: .tutorial(step: 0), state: finished(.south))
        XCTAssertTrue(events.isEmpty)
    }

    func testUnfinishedGamesReportNothing() {
        player.gameFinished(mode: vs(.beginner), state: .initial)
        XCTAssertTrue(events.isEmpty)
    }

    func testJourneyStarsAndChapters() {
        player.journeyProgress(totalStars: 5, chapterCompleted: nil)
        player.journeyProgress(totalStars: 9, chapterCompleted: 0)
        XCTAssertEqual(services.scores.map(\.0), [5, 9])
        XCTAssertEqual(events, [.journeyChapterCompleted(chapter: 1)])
        XCTAssertEqual(services.achievements, [GameCenterID.Achievement.firstChapter])
    }

    func testDailyRiddleSubmitsTheStreakOthersDoNot() throws {
        let puzzle = Puzzle(id: "x", kind: .captureInOne, houses: Array(repeating: 4, count: 12), stores: [0, 0],
                            toMove: .south, solution: Move(player: .south, house: 0), target: 2, difficulty: 1)
        player.riddleSolved(puzzle, daily: false, streak: 0)
        player.riddleSolved(puzzle, daily: true, streak: 3)
        XCTAssertEqual(events, [.riddleSolved(kind: "captureInOne", daily: false), .riddleSolved(kind: "captureInOne", daily: true)])
        XCTAssertEqual(services.scores.map(\.0), [3])
        XCTAssertEqual(services.scores.first?.1, GameCenterID.Leaderboard.riddleStreak)
    }

    func testLessonAndTips() {
        player.lessonCompleted(rules: .namNam)
        player.tipJarViewed()
        player.tipPurchased(productID: "com.richardforjoe.oware.tip.medium")
        player.tipPurchased(productID: nil)
        XCTAssertEqual(events, [.lessonCompleted(rules: "namNam"), .tipJarViewed, .tipPurchased(tier: "medium"), .tipPurchased(tier: "unknown")])
        XCTAssertEqual(services.achievements, [GameCenterID.Achievement.lessonDone])
    }

    // MARK: Analytics switch

    func testAnalyticsSendsOnlyWhenEnabled() {
        var sent: [String] = []
        let analytics = Analytics()
        analytics.backend = SpyBackend { name, _ in sent.append(name) }
        analytics.track(.appLaunched)
        analytics.isEnabled = false
        analytics.track(.tipJarViewed)
        XCTAssertEqual(sent, ["app.launched"])
    }

    func testTheSDKIsNotStartedWhileAnalyticsAreOff() {
        let analytics = Analytics()
        var built = 0
        analytics.configure(enabled: false, bundle: Bundle(for: PlayerEventsTests.self))
        analytics.track(.appLaunched)
        XCTAssertNil(analytics.backend, "off (as in every test launch): nothing is started")
        analytics.isEnabled = true
        analytics.backend = SpyBackend { _, _ in built += 1 }
        analytics.track(.appLaunched)
        XCTAssertEqual(built, 1)
    }

    func testNoAppIDMeansNoAnalytics() {
        XCTAssertNil(TelemetryDeckBackend(appID: nil))
        XCTAssertNil(TelemetryDeckBackend(appID: ""))
        XCTAssertNil(TelemetryDeckBackend(appID: "$(TELEMETRYDECK_APP_ID)"))
    }

    func testEventsCarryNoPersonalData() {
        let all: [AnalyticsEvent] = [.appLaunched, .gameFinished(mode: "computer", level: "master", result: "win", rules: "namNam"),
                                     .journeyChapterCompleted(chapter: 2), .riddleSolved(kind: "feedOrLose", daily: true),
                                     .lessonCompleted(rules: "abapa"), .tipJarViewed, .tipPurchased(tier: "large")]
        XCTAssertEqual(Set(all.map(\.name)).count, 7, "seven distinct events")
        let keys = Set(all.flatMap { $0.parameters.keys })
        XCTAssertEqual(keys, ["mode", "level", "result", "rules", "chapter", "kind", "daily", "tier"])
    }

    /// App Review 5.1.1(ii): nothing is collected until the player agrees.
    func testUsageStatsAreOffUntilThePlayerAgrees() {
        let d = TestSupport.defaults()
        let settings = AppSettings(defaults: d, testMode: false)
        XCTAssertFalse(settings.shareUsageStats || settings.effectiveUsageStats, "off before any answer")
        XCTAssertTrue(settings.shouldAskUsageStats)
        settings.answerUsageStats(true)
        XCTAssertTrue(settings.effectiveUsageStats)
        XCTAssertFalse(settings.shouldAskUsageStats, "asked once")
        let reopened = AppSettings(defaults: d, testMode: false)
        XCTAssertTrue(reopened.shareUsageStats && !reopened.shouldAskUsageStats, "remembered")
        reopened.answerUsageStats(false)
        XCTAssertFalse(AppSettings(defaults: d, testMode: false).shareUsageStats)
    }

    /// Earlier builds saved "on" without asking; that is not consent.
    func testAnOldUnaskedOnIsNotConsent() {
        let d = TestSupport.defaults()
        d.set(true, forKey: "shareUsageStats")
        let settings = AppSettings(defaults: d, testMode: false)
        XCTAssertFalse(settings.shareUsageStats)
        XCTAssertTrue(settings.shouldAskUsageStats)
    }

    func testTestLaunchesNeitherSendNorAsk() {
        let settings = AppSettings(defaults: TestSupport.defaults(), testMode: true)
        settings.answerUsageStats(true)
        XCTAssertFalse(settings.effectiveUsageStats)
        XCTAssertFalse(AppSettings(defaults: TestSupport.defaults(), testMode: true).shouldAskUsageStats)
    }

    // MARK: Online access ("the host pays")

    func testOnlinePolicy() {
        let policy = OnlinePolicy()
        XCTAssertTrue(policy.canHost(purchased: true, founding: false))
        XCTAssertFalse(policy.canHost(purchased: false, founding: true), "founding players are not included unless switched on")
        XCTAssertTrue(policy.canJoin(invitedByPlayerWhoCanHost: true, purchased: false, founding: false), "invited friends play free")
        XCTAssertFalse(policy.canJoin(invitedByPlayerWhoCanHost: false, purchased: false, founding: false))
        let generous = OnlinePolicy(hostPays: true, foundingPlayersIncluded: true)
        XCTAssertTrue(generous.canHost(purchased: false, founding: true))
        XCTAssertFalse(FeatureFlags.onlinePlay, "online play stays hidden until it ships")
    }
}
