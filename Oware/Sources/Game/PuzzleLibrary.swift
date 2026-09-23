import Foundation
import Observation
import OwareAI

/// Loads the shipped puzzle set and remembers which ones the player has solved.
@MainActor
@Observable
final class PuzzleLibrary {
    private(set) var puzzleSet: PuzzleSet
    private(set) var solvedIDs: Set<String>
    private let defaults: UserDefaults
    private static let solvedKey = "solvedPuzzleIDs"

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        solvedIDs = Set(defaults.stringArray(forKey: Self.solvedKey) ?? [])
        if let url = bundle.url(forResource: "puzzles", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PuzzleSet.self, from: data) {
            puzzleSet = decoded
        } else {
            puzzleSet = PuzzleSet(puzzles: [])
        }
    }

    var puzzles: [Puzzle] { puzzleSet.puzzles }
    func puzzles(of kind: Puzzle.Kind) -> [Puzzle] { puzzleSet.puzzles(of: kind) }
    func isSolved(_ puzzle: Puzzle) -> Bool { solvedIDs.contains(puzzle.id) }
    func solvedCount(of kind: Puzzle.Kind) -> Int { puzzles(of: kind).filter(isSolved).count }

    func markSolved(_ puzzle: Puzzle) {
        solvedIDs.insert(puzzle.id)
        defaults.set(Array(solvedIDs).sorted(), forKey: Self.solvedKey)
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
