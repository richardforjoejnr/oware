/// AI strength levels: a ladder of even steps from "a first-timer usually wins" to a real challenge.
///
/// Tuned 2026-10-03 after a new player could not win: the old ladder jumped from Novice (1 move ahead,
/// 40% slips) to Intermediate (4 ahead, 10%), which simulated first-time and casual players won 0–3%
/// of the time. Measured with `BalanceTests`' simulated players (a "first-timer" plays a random move
/// half the time, otherwise the obvious capture; a "casual" player always takes the obvious capture),
/// casual win rates are now about: Novice 85–90%, Intermediate 70%, the Journey's in-between 55–75%,
/// Strategist 15–40%, the Journey's master 5–20%, Grandmaster 0%.
public enum Difficulty: Int, Sendable, Codable, CaseIterable, Comparable {
    case beginner = 0
    case learner
    case player
    case strong
    case master
    case grandmaster

    public static func < (lhs: Difficulty, rhs: Difficulty) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Maximum search depth in plies.
    public var maxDepth: Int {
        switch self {
        case .beginner: 1
        case .learner: 1
        case .player: 2
        case .strong: 3
        case .master: 4
        case .grandmaster: 12
        }
    }

    /// Thinking time budget.
    public var timeBudget: Duration {
        switch self {
        case .beginner, .learner: .milliseconds(100)
        case .player: .milliseconds(200)
        case .strong: .milliseconds(300)
        case .master: .milliseconds(400)
        case .grandmaster: .milliseconds(3000)
        }
    }

    /// Probability of playing a random legal move instead of the best one.
    public var blunderRate: Double {
        switch self {
        case .beginner: 0.65
        case .learner: 0.40
        case .player: 0.50
        case .strong: 0.40
        case .master: 0.25
        case .grandmaster: 0
        }
    }

    public var displayName: String {
        switch self {
        // The owner's names (2026-09-27). Only four levels are offered in the app; the two in
        // between are used by Journey opponents and share the nearest name.
        case .beginner: "Novice"
        case .learner, .player: "Intermediate"
        case .strong, .master: "Strategist"
        case .grandmaster: "Grandmaster"
        }
    }

    /// The levels a player can pick: Novice, Intermediate, Strategist, Grandmaster.
    public static let menuLevels: [Difficulty] = [.beginner, .learner, .strong, .grandmaster]

    /// The picker level this one is shown as (older saves may hold an in-between level).
    public var menuLevel: Difficulty {
        switch self {
        case .beginner: .beginner
        case .learner, .player: .learner
        case .strong, .master: .strong
        case .grandmaster: .grandmaster
        }
    }
}
