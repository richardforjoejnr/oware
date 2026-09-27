import Foundation
import TelemetryDeck

/// Everything the app reports, in one place. Only what was played and how it went: no names, no
/// contacts, no location, nothing typed. See docs/lelu-oware/privacy.md.
enum AnalyticsEvent: Equatable, Sendable {
    case appLaunched
    case gameFinished(mode: String, level: String?, result: String, rules: String)
    case journeyChapterCompleted(chapter: Int)
    case riddleSolved(kind: String, daily: Bool)
    case lessonCompleted(rules: String)
    case tipJarViewed
    case tipPurchased(tier: String)

    var name: String {
        switch self {
        case .appLaunched: "app.launched"
        case .gameFinished: "game.finished"
        case .journeyChapterCompleted: "journey.chapterCompleted"
        case .riddleSolved: "riddle.solved"
        case .lessonCompleted: "lesson.completed"
        case .tipJarViewed: "tipJar.viewed"
        case .tipPurchased: "tipJar.purchased"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .appLaunched, .tipJarViewed: [:]
        case let .gameFinished(mode, level, result, rules):
            ["mode": mode, "result": result, "rules": rules].merging(level.map { ["level": $0] } ?? [:]) { a, _ in a }
        case let .journeyChapterCompleted(chapter): ["chapter": "\(chapter)"]
        case let .riddleSolved(kind, daily): ["kind": kind, "daily": daily ? "yes" : "no"]
        case let .lessonCompleted(rules): ["rules": rules]
        case let .tipPurchased(tier): ["tier": tier]
        }
    }
}

protocol AnalyticsBackend {
    func send(_ name: String, parameters: [String: String])
}

/// TelemetryDeck: anonymous, no consent prompt needed; the app ID comes from the build setting
/// `TELEMETRYDECK_APP_ID` (Info.plist key `TelemetryDeckAppID`). Empty means analytics are off.
struct TelemetryDeckBackend: AnalyticsBackend {
    init?(appID: String?) {
        guard let appID, !appID.isEmpty, !appID.hasPrefix("$(") else { return nil }
        TelemetryDeck.initialize(config: .init(appID: appID))
    }

    func send(_ name: String, parameters: [String: String]) {
        TelemetryDeck.signal(name, parameters: parameters)
    }
}

/// The one door analytics go through, so the vendor can be swapped or everything switched off here.
@MainActor
final class Analytics {
    static let shared = Analytics()

    var backend: AnalyticsBackend?
    /// Follows Settings ▸ Share anonymous usage stats.
    var isEnabled = true

    func configure(enabled: Bool, bundle: Bundle = .main) {
        isEnabled = enabled
        backend = TelemetryDeckBackend(appID: bundle.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String)
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled, let backend else { return }
        backend.send(event.name, parameters: event.parameters)
    }
}
