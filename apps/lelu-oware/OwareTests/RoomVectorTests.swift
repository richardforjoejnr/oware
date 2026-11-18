import MatchKit
import OwareEngine
import XCTest
@testable import Oware

/// What two phones playing Oware send each other, as it is on the wire: every example in
/// `shared/vectors/room-v2` is read by this app and written back the same. An Android app will
/// read and write the same files, so a test failing here means a new room protocol version is
/// needed, not a new example.
final class RoomVectorTests: XCTestCase {
    private typealias Message = RoomMessage<OwareTable, TableIntent>

    private static let folder = URL(fileURLWithPath: #filePath)   // …/apps/lelu-oware/OwareTests/RoomVectorTests.swift
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("shared/vectors/room-v2", isDirectory: true)

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: Self.folder.appendingPathComponent(name + ".json"))
    }

    private func message(_ name: String) throws -> Message {
        try JSONDecoder().decode(Envelope<Message>.self, from: data(name)).body
    }

    private func table(_ name: String) throws -> OwareTable {
        guard case let .snapshot(table) = try message(name) else { throw XCTSkip("\(name) is not a snapshot") }
        return table
    }

    private var names: [String] {
        get throws {
            let top = try FileManager.default.contentsOfDirectory(atPath: Self.folder.path)
            let oware = try FileManager.default.contentsOfDirectory(atPath: Self.folder.appendingPathComponent("oware").path)
            return (top + oware.map { "oware/" + $0 }).filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
        }
    }

    private func json(_ data: Data) throws -> NSObject {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSObject)
    }

    func testEveryExampleIsReadAndWrittenBackTheSame() throws {
        let names = try names
        XCTAssertEqual(names.count, 21, "an example was added or removed")
        XCTAssertTrue(names.contains("player"), "a phone's player number, told once seated")
        for name in names {
            let example = try data(name)
            let envelope = try JSONDecoder().decode(Envelope<Message>.self, from: example)
            let written = try JSONEncoder().encode(envelope)
            XCTAssertEqual(try json(written), try json(example), name)
        }
    }

    func testIntentsSayWhatTheExamplesSay() throws {
        func intent(_ name: String) throws -> TableIntent {
            guard case let .intent(intent) = try message("oware/" + name) else { throw XCTSkip("\(name) is not an intent") }
            return intent
        }
        XCTAssertEqual(try intent("intent-pace"), .pace(0.6))
        XCTAssertEqual(try intent("intent-ready"), .ready(stateHash: "2de35c20d63699b4"))
        XCTAssertEqual(try intent("intent-play"), .game(.play(house: 9)))
        XCTAssertEqual(try intent("intent-resign"), .game(.resign))
        XCTAssertEqual(try intent("intent-rematch"), .game(.rematch))
        XCTAssertEqual(try intent("intent-decline-rematch"), .declineRematch)
    }

    func testSnapshotsSayWhatTheExamplesSay() throws {
        let id = try XCTUnwrap(UUID(uuidString: "6F1E2D3C-4B5A-4978-8A69-5B4C3D2E1F00"))
        let opening = OwareTable.opening(OwareMatch(rules: .abapa, matchID: id), paces: [.south: 0.35])
        XCTAssertEqual(try table("oware/snapshot-opening"), opening)

        var playing = opening
        playing.match.houses = [2, 9]
        playing.paces[.north] = 0.6
        playing.ready = [.south, .north]
        playing.stateHash = "1a94966d4dd55eca"
        XCTAssertEqual(try table("oware/snapshot-playing"), playing)

        var resigned = playing
        resigned.match.resignedBy = .north
        resigned.rematchAsked = [.south]
        resigned.stateHash = "63e16950d99c7d58"
        XCTAssertEqual(try table("oware/snapshot-resigned"), resigned)

        // North said not now to South's request: nobody is asking, and it says who answered.
        var declined = resigned
        declined.rematchAsked = []
        declined.rematchDeclinedBy = .north
        declined.rematchRound = 1
        XCTAssertEqual(try table("oware/snapshot-rematch-declined"), declined)

        // South asked again and nobody answered for a minute.
        var lapsed = resigned
        lapsed.rematchAsked = []
        lapsed.rematchLapsedFor = .south
        lapsed.rematchRound = 2
        XCTAssertEqual(try table("oware/snapshot-rematch-lapsed"), lapsed)

        var outOfStep = OwareTable(match: OwareMatch(rules: .namNam, starter: .north, matchID: id, game: 2))
        outOfStep.isOutOfStep = true
        XCTAssertEqual(try table("oware/snapshot-out-of-step"), outOfStep)

        guard case let .welcome(seat, _, names, snapshot) = try message("oware/welcome") else { return XCTFail("welcome") }
        XCTAssertEqual(seat, 1)
        XCTAssertEqual(names, [0: "Ama", 1: "Kofi"])
        XCTAssertEqual(snapshot, opening)
    }

    /// The fingerprints in the examples are the engine's own, so another engine (Kotlin) that
    /// replays the same moves must arrive at the same text.
    func testTheFingerprintsInTheExamplesAreTheEnginesOwn() throws {
        for name in ["snapshot-opening", "snapshot-playing", "snapshot-resigned", "snapshot-rematch-declined", "snapshot-rematch-lapsed"] {
            let table = try table("oware/" + name)
            XCTAssertEqual(table.stateHash, try table.match.state().fingerprint, name)
        }
    }
}
