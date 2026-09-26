/// AI strength levels. Depth and time budgets are tuned so Beginner is genuinely beatable
/// and Grandmaster is a real challenge on a phone.
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
        case .learner: 2
        case .player: 4
        case .strong: 6
        case .master: 9
        case .grandmaster: 12
        }
    }

    /// Thinking time budget.
    public var timeBudget: Duration {
        switch self {
        case .beginner: .milliseconds(100)
        case .learner: .milliseconds(200)
        case .player: .milliseconds(400)
        case .strong: .milliseconds(800)
        case .master: .milliseconds(1500)
        case .grandmaster: .milliseconds(3000)
        }
    }

    /// Probability of playing a random legal move instead of the best one.
    public var blunderRate: Double {
        switch self {
        case .beginner: 0.40
        case .learner: 0.25
        case .player: 0.10
        case .strong: 0.03
        case .master, .grandmaster: 0
        }
    }

    public var displayName: String {
        switch self {
        case .beginner: "Beginner"
        case .learner: "Learner"
        case .player: "Player"
        case .strong: "Strong"
        case .master: "Master"
        case .grandmaster: "Grandmaster"
        }
    }
}
