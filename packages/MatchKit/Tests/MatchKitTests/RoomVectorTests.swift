import Foundation
import Testing
@testable import MatchKit

/// The room protocol, version 2, as it is on the wire: every example in `shared/vectors/room-v2`
/// is read, and written back exactly as it was. The Android app reads and writes the same files,
/// so a change here is a new protocol version, never an accident.
@Suite("Room messages match shared/vectors/room-v2")
struct RoomVectorTests {
    typealias Message = RoomMessage<JSONValue, JSONValue>
    static let files = Vectors.files(in: "room-v2")

    @Test func everyKindOfMessageHasAnExample() throws {
        var kinds: Set<String> = []
        for file in Self.files {
            guard case let .object(top) = try JSONValue(json: file.data), case let .object(body)? = top["body"],
                  case let .string(type)? = body["type"] else {
                Issue.record("\(file.name) is not an envelope")
                continue
            }
            kinds.insert(type)
            if case let .string(reason)? = body["reason"] { kinds.insert("refused." + reason) }
        }
        #expect(kinds == ["hello", "welcome", "refused", "refused.roomFull", "refused.declined", "refused.needsUpdate",
                          "intent", "snapshot", "ping", "bye"])
    }

    @Test(arguments: files)
    func isReadAndWrittenBackTheSame(_ file: Vectors.File) throws {
        let envelope = try JSONDecoder().decode(Envelope<Message>.self, from: file.data)
        #expect(envelope.protocolVersion == 2)
        #expect(try JSONValue(writing: envelope) == JSONValue(json: file.data))
        // The version is read on its own first, before the body.
        #expect(try JSONDecoder().decode(EnvelopeHeader.self, from: file.data).protocolVersion == 2)
    }

    @Test func helloAndWelcomeCarryWhatTheExamplesSay() throws {
        func message(_ name: String) throws -> Message {
            let file = try #require(Self.files.first { $0.name == name })
            return try JSONDecoder().decode(Envelope<Message>.self, from: file.data).body
        }
        let token = try #require(UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D"))
        guard case .hello("Kofi", nil) = try message("hello.json") else { Issue.record("hello"); return }
        guard case .hello("Kofi", token) = try message("hello-rejoin.json") else { Issue.record("hello-rejoin"); return }
        guard case let .welcome(seat, seatToken, names, _) = try message("oware/welcome.json") else {
            Issue.record("welcome")
            return
        }
        #expect(seat == 1)
        #expect(seatToken == token)
        #expect(names == [0: "Ama", 1: "Kofi"])
        guard case .refused(.needsUpdate(hostVersion: 2)) = try message("refused-needs-update.json") else {
            Issue.record("refused")
            return
        }
    }
}
