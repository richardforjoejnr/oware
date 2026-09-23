import Foundation
import OwareEngine
import OwareAI

// Minimal terminal tool for exercising the engine and AI without Xcode.
//
//   swift run oware selfplay [--games N] [--south LEVEL] [--north LEVEL] [--seed S]
//   swift run oware play [--level LEVEL]          # you are south (A), type A1…A6
//   swift run oware replay "A1 B3 A6 ..."          # print the board after each move

func level(_ name: String?) -> Difficulty {
    guard let name else { return .player }
    return Difficulty.allCases.first { $0.displayName.lowercased() == name.lowercased() } ?? .player
}

func option(_ flag: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "selfplay"

switch command {
case "selfplay":
    let games = Int(option("--games", in: args) ?? "20") ?? 20
    let south = AIPlayer(difficulty: level(option("--south", in: args)))
    let north = AIPlayer(difficulty: level(option("--north", in: args)))
    let seed = UInt64(option("--seed", in: args) ?? "1") ?? 1
    var wins = [0, 0], draws = 0, totalPlies = 0
    let clock = ContinuousClock()
    let start = clock.now
    for game in 0..<games {
        var state = GameState.initial
        var plies = 0
        while !state.isOver {
            let ai = state.sideToMove == .south ? south : north
            guard let move = ai.chooseMove(for: state, seed: seed &+ UInt64(game)) else { break }
            try! state.apply(move)
            plies += 1
            precondition(state.totalSeeds == 48, "seed conservation violated")
        }
        totalPlies += plies
        switch state.outcome! {
        case let .win(p, _): wins[p.rawValue] += 1
        case .draw: draws += 1
        }
    }
    let elapsed = clock.now - start
    print("\(games) games: South(\(south.difficulty.displayName)) \(wins[0])  North(\(north.difficulty.displayName)) \(wins[1])  draws \(draws)")
    print("avg plies \(totalPlies / max(games, 1)), elapsed \(elapsed)")

case "play":
    let ai = AIPlayer(difficulty: level(option("--level", in: args)))
    var state = GameState.initial
    print("You are A (south). Type a house like A3. Ctrl-D to quit.\n")
    while !state.isOver {
        print(state)
        if state.sideToMove == .south {
            print("Legal: \(state.legalMoves().map(\.notation).joined(separator: " "))")
            print("> ", terminator: "")
            guard let line = readLine() else { exit(0) }
            guard let move = Move(notation: line) else { print("Not a move."); continue }
            do {
                let events = try state.apply(move)
                for e in events { if case let .capture(h, n, _) = e { print("  captured \(n) from house \(h)") } }
            } catch { print("Illegal: \(error)") }
        } else {
            let analysis = ai.analyse(state)!
            print("AI plays \(analysis.move.notation) (depth \(analysis.depth), score \(analysis.score), nodes \(analysis.nodes))")
            try! state.apply(analysis.move)
        }
        print()
    }
    print(state)
    print("Result: \(state.outcome!)")

case "replay":
    guard let notation = args.dropFirst().first, let record = GameRecord(notation: notation) else {
        print("usage: oware replay \"A1 B3 ...\""); exit(1)
    }
    do {
        for (i, s) in try record.states().enumerated() {
            print("Move \(i)\(i > 0 ? " (\(record.moves[i - 1].notation))" : "")")
            print(s)
            print()
        }
    } catch { print("Illegal move in record: \(error)"); exit(1) }

default:
    print("commands: selfplay | play | replay"); exit(1)
}
