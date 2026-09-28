import Foundation
import Testing
@testable import OwareEngine

/// A damaged or hand-edited save must be refused with an error, never crash the app on load.
@Suite("Corrupt saves")
struct CorruptSaveTests {
    private struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    /// A real mid-game save (Nam-Nam, round 2) as a JSON dictionary.
    private func savedJSON() throws -> [String: Any] {
        var s = GameState.initial(rules: .namNam)
        var rng = LCG(s: 1)
        while s.round == 1, !s.isOver, let m = s.legalMoves().randomElement(using: &rng) { try s.apply(m) }
        if let m = s.legalMoves().first { try s.apply(m) }
        return try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: Any) throws -> T {
        try JSONDecoder().decode(type, from: try JSONSerialization.data(withJSONObject: json))
    }

    @Test("Moves off the board are refused", arguments: [
        ["player": 0, "absoluteIndex": 12], ["player": 1, "absoluteIndex": -1],
        ["player": 0, "house": 6], ["player": 1, "house": -3], ["player": 2, "absoluteIndex": 3],
    ] as [[String: Int]])
    func badMoves(json: [String: Int]) {
        #expect(throws: DecodingError.self) { try decode(Move.self, json) }
    }

    @Test("Good moves, old and new format, still load")
    func goodMoves() throws {
        #expect(try decode(Move.self, ["player": 1, "absoluteIndex": 11]) == Move(player: .north, absoluteHouse: 11))
        #expect(try decode(Move.self, ["player": 1, "house": 2]) == Move(notation: "B3"))
    }

    @Test("Damaged positions are refused", arguments: [
        "houses: 11", "houses: negative", "houses: huge", "stores: 3", "stores: negative",
        "territory: 5", "moveNumber: negative", "round: 0", "lastMove: off board",
    ])
    func damagedStates(damage: String) throws {
        var json = try savedJSON()
        switch damage {
        case "houses: 11": json["houses"] = Array(repeating: 4, count: 11)
        case "houses: negative": json["houses"] = [-4] + Array(repeating: 4, count: 11)
        case "houses: huge": json["houses"] = [Int.max] + Array(repeating: 4, count: 11)
        case "stores: 3": json["stores"] = [0, 0, 0]
        case "stores: negative": json["stores"] = [-1, 1]
        case "territory: 5": json["territory"] = [0, 0, 1, 1, 1]
        case "moveNumber: negative": json["moveNumber"] = -7
        case "round: 0": json["round"] = 0
        case "lastMove: off board": json["lastMove"] = ["player": 0, "absoluteIndex": 40]
        default: Issue.record("unknown damage \(damage)")
        }
        #expect(throws: DecodingError.self) { try decode(GameState.self, json) }
    }

    @Test("Saves with the old, unused lastCapturer key still load")
    func oldLastCapturerKey() throws {
        var json = try savedJSON()
        json["lastCapturer"] = 1
        let state = try decode(GameState.self, json)
        #expect(state.totalSeeds == 48)
    }

    /// Random damage to a real save: decoding either throws or gives a position that can be played
    /// (including by feeding it moves that are not legal) without crashing.
    @Test("Randomly damaged saves throw or play on; they never crash")
    func fuzzedSaves() throws {
        var rng = LCG(s: 99)
        let original = try savedJSON()
        let keys = Array(original.keys).sorted()
        var loaded = 0, refused = 0
        for _ in 0..<400 {
            var json = original
            for _ in 0...(rng.next() % 3) {
                let key = keys[Int(rng.next() % UInt64(keys.count))]
                let values: [Any] = [-1, 0, 1, 5, 12, 48, 49, 1_000_000, "x", NSNull(), [Int](), [4, 4],
                                     Array(repeating: 1, count: 12), Array(repeating: 0, count: 12), [0, 1]]
                json[key] = rng.next() % 4 == 0 ? nil : values[Int(rng.next() % UInt64(values.count))]
            }
            guard var state = try? decode(GameState.self, json) else { refused += 1; continue }
            loaded += 1
            _ = state.description
            _ = state.positionKey
            for _ in 0..<20 {
                let house = Int(rng.next() % 12)
                let move = Move(player: rng.next() % 2 == 0 ? .south : .north, absoluteHouse: house)
                _ = try? state.apply(move)
                if let legal = state.legalMoves().first { _ = try? state.apply(legal) }
            }
        }
        #expect(loaded > 0 && refused > 0)
    }

    @Test("Garbage is refused")
    func garbage() {
        for text in ["", "{}", "[]", "null", "{\"houses\": 3}", "not json"] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(GameState.self, from: Data(text.utf8)) }
        }
    }
}
