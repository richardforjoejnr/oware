import Foundation
import Observation
import OwareAI
import OwareEngine

/// Loads the shipped puzzle sets (one per rules variant) and remembers which ones the player has solved.
@MainActor
@Observable
final class PuzzleLibrary {
    /// Which rules the riddles are shown for; set from Settings.
    var variant: RuleSet.Variant = .namNam
    private let sets: [RuleSet.Variant: PuzzleSet]
    var puzzleSet: PuzzleSet { sets[variant] ?? PuzzleSet(puzzles: []) }
    private(set) var solvedIDs: Set<String>
    private let defaults: UserDefaults
    private static let solvedKey = "solvedPuzzleIDs"
    static let streakKey = "dailyStreak"
    static let lastDailyDayKey = "lastDailySolvedDay"
    /// Days in a row on which today's riddle was solved (as of the last daily solved).
    private(set) var dailyStreak: Int

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        solvedIDs = Set(defaults.stringArray(forKey: Self.solvedKey) ?? [])
        dailyStreak = defaults.integer(forKey: Self.streakKey)
        func load(_ name: String) -> PuzzleSet {
            guard let url = bundle.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(PuzzleSet.self, from: data) else { return PuzzleSet(puzzles: []) }
            return decoded
        }
        sets = [.abapa: load("puzzles"), .namNam: load("puzzles-namnam")]
    }

    var puzzles: [Puzzle] { puzzleSet.puzzles }
    func puzzles(of kind: Puzzle.Kind) -> [Puzzle] { puzzleSet.puzzles(of: kind) }
    func isSolved(_ puzzle: Puzzle) -> Bool { solvedIDs.contains(puzzle.id) }
    func solvedCount(of kind: Puzzle.Kind) -> Int { puzzles(of: kind).filter(isSolved).count }

    func markSolved(_ puzzle: Puzzle, today: Int = PuzzleLibrary.dayNumber()) {
        solvedIDs.insert(puzzle.id)
        defaults.set(Array(solvedIDs).sorted(), forKey: Self.solvedKey)
        if isDaily(puzzle, today: today) { extendStreak(today: today) }
    }

    func isDaily(_ puzzle: Puzzle, today: Int = PuzzleLibrary.dayNumber()) -> Bool {
        puzzleSet.daily(dayNumber: today)?.id == puzzle.id
    }

    /// The streak as it stands today: it lapses once a whole day passes without the daily riddle.
    func currentStreak(today: Int = PuzzleLibrary.dayNumber()) -> Int {
        guard let last = defaults.object(forKey: Self.lastDailyDayKey) as? Int, last >= today - 1 else { return 0 }
        return dailyStreak
    }

    private func extendStreak(today: Int) {
        let last = defaults.object(forKey: Self.lastDailyDayKey) as? Int
        if last == today { return }
        dailyStreak = last == today - 1 ? dailyStreak + 1 : 1
        defaults.set(dailyStreak, forKey: Self.streakKey)
        defaults.set(today, forKey: Self.lastDailyDayKey)
    }

    /// The next unsolved puzzle of the same kind after `puzzle`, wrapping around; nil if all solved.
    func next(after puzzle: Puzzle) -> Puzzle? {
        let list = puzzles(of: puzzle.kind)
        guard let index = list.firstIndex(of: puzzle) else { return nil }
        for offset in 1..<max(list.count, 2) {
            let candidate = list[(index + offset) % list.count]
            if !isSolved(candidate) { return candidate }
        }
        return nil
    }

    /// Days since 1 January 2026 in the device's calendar; same puzzle for everyone on the same day.
    static func dayNumber(for date: Date = .now, calendar: Calendar = .current) -> Int {
        let epoch = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: epoch), to: calendar.startOfDay(for: date)).day ?? 0
    }

    var daily: Puzzle? { puzzleSet.daily(dayNumber: Self.dayNumber()) }
    var dailySolved: Bool { daily.map(isSolved) ?? false }
}
