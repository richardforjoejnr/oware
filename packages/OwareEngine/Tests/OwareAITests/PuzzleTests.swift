import Testing
import Foundation
import OwareEngine
@testable import OwareAI

@Suite("Puzzles")
struct PuzzleTests {
    static let generated = PuzzleGenerator(seed: 99).generate(perKind: 3, maxGames: 600)

    @Test("Generator produces every kind with unique, verifiable answers")
    func generatorProducesAllKinds() {
        let set = Self.generated
        for kind in Puzzle.Kind.allCases {
            #expect(set.puzzles(of: kind).count == 3, "\(kind)")
        }
        for puzzle in set.puzzles {
            let state = puzzle.state
            #expect(state.totalSeeds == 48)
            #expect(state.isLegal(puzzle.solution), "\(puzzle.id) solution must be legal")
            #expect(PuzzleGenerator.classify(state, as: puzzle.kind, index: 1)?.solution == puzzle.solution, "\(puzzle.id) must re-classify to the same answer")
        }
    }

    @Test("Capture-in-one solutions really capture the most seeds")
    func captureInOneIsBest() {
        for puzzle in Self.generated.puzzles(of: .captureInOne) {
            let values = PuzzleGenerator.captureValues(puzzle.state)
            let best = values.max { $0.1 < $1.1 }!
            #expect(best.0 == puzzle.solution)
            #expect(best.1 == puzzle.target)
        }
    }

    @Test("Escape-the-trap solutions leave the opponent no capture")
    func trapSolutionsAreSafe() {
        for puzzle in Self.generated.puzzles(of: .escapeTheTrap) {
            #expect(PuzzleGenerator.opponentBestCapture(after: puzzle.solution, in: puzzle.state) == 0)
        }
    }

    @Test("Generation is deterministic for a seed")
    func deterministic() {
        let again = PuzzleGenerator(seed: 99).generate(perKind: 3, maxGames: 600)
        #expect(again == Self.generated)
    }

    @Test("Daily pick is stable per day and round-trips through JSON")
    func dailyAndCodable() throws {
        let set = Self.generated
        #expect(set.daily(dayNumber: 266) == set.daily(dayNumber: 266))
        let data = try JSONEncoder().encode(set)
        let back = try JSONDecoder().decode(PuzzleSet.self, from: data)
        #expect(back == set)
    }
}
