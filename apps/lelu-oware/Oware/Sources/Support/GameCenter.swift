import GameKit
import Observation
import UIKit

/// Leaderboard and achievement ids. They must match what is set up in App Store Connect
/// (Features ▸ Game Center); see docs/STATUS.md for the list to create.
enum GameCenterID {
    enum Leaderboard {
        static let riddleStreak = "com.richardforjoe.oware.leaderboard.riddleStreak"
        static let journeyStars = "com.richardforjoe.oware.leaderboard.journeyStars"
        static let grandmasterWins = "com.richardforjoe.oware.leaderboard.grandmasterWins"
    }
    enum Achievement {
        static let firstWin = "com.richardforjoe.oware.achievement.firstWin"
        static let lessonDone = "com.richardforjoe.oware.achievement.lessonDone"
        static let firstRiddle = "com.richardforjoe.oware.achievement.firstRiddle"
        static let firstChapter = "com.richardforjoe.oware.achievement.firstChapter"
        static let beatGrandmaster = "com.richardforjoe.oware.achievement.beatGrandmaster"
        static let allTwelveHouses = "com.richardforjoe.oware.achievement.allTwelveHouses"
    }
}

/// What the game tells Game Center. A protocol so tests can record calls instead.
@MainActor
protocol GameServices: AnyObject {
    func submit(_ score: Int, to leaderboard: String)
    func unlock(_ achievement: String)
}

/// Game Center via GameKit. Signing in is Apple's own sheet; if the player declines, nothing is
/// sent and the game carries on as before.
@MainActor
@Observable
final class GameCenter: GameServices {
    static let shared = GameCenter()
    private(set) var isAuthenticated = false

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            Task { @MainActor in
                if let viewController { Self.present(viewController) }
                GameCenter.shared.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    func submit(_ score: Int, to leaderboard: String) {
        guard isAuthenticated else { return }
        Task { try? await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboard]) }
    }

    func unlock(_ achievement: String) {
        guard isAuthenticated else { return }
        let a = GKAchievement(identifier: achievement)
        a.percentComplete = 100
        a.showsCompletionBanner = true
        Task { try? await GKAchievement.report([a]) }
    }

    /// Apple's Game Center dashboard: leaderboards, achievements, friends.
    func showDashboard() {
        guard isAuthenticated else { authenticate(); return }
        GKAccessPoint.shared.trigger(state: .dashboard) {}
    }

    private static func present(_ viewController: UIViewController) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(viewController, animated: true)
    }
}
