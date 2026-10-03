import LudoAI

/// Where rolls come from: a fair die, or a script (UI tests and screenshots: `--dice=6,4,3`).
@MainActor
protocol DiceSource: AnyObject {
    func roll() -> Int
}

final class RandomDice: DiceSource {
    private var rng = SystemRandomNumberGenerator()
    func roll() -> Int { Int.random(in: 1...6, using: &rng) }
}

/// Plays the given faces in order, then starts again from the first.
final class ScriptedDice: DiceSource {
    private let faces: [Int]
    private var next = 0

    init(_ faces: [Int]) {
        precondition(!faces.isEmpty && faces.allSatisfy { (1...6).contains($0) })
        self.faces = faces
    }

    func roll() -> Int {
        defer { next = (next + 1) % faces.count }
        return faces[next]
    }

    /// Faces from a `--dice=6,4,3` argument; nil unless every face is 1…6.
    nonisolated static func parse(_ argument: String) -> [Int]? {
        guard argument.hasPrefix("--dice=") else { return nil }
        let faces = argument.dropFirst("--dice=".count).split(separator: ",").compactMap { Int($0) }
        return !faces.isEmpty && faces.allSatisfy({ (1...6).contains($0) }) ? faces : nil
    }
}
