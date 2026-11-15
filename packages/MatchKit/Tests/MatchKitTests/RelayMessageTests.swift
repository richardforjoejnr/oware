import Foundation
import Testing
@testable import MatchKit

/// What a phone and the relay say to each other (docs/ONLINE_PLAY.md §5), held to the examples in
/// `shared/vectors/relay-v1`. The relay's own tests read the same files.
@Suite("Relay messages match shared/vectors/relay-v1")
struct RelayMessageTests {
    static let toRelay = Vectors.files(in: "relay-v1/to-relay")
    static let fromRelay = Vectors.files(in: "relay-v1/from-relay")

    private func request(_ name: String) throws -> RelayRequest {
        let file = try #require(Self.toRelay.first { $0.name == name + ".json" }, "no example \(name)")
        return try JSONDecoder().decode(RelayRequest.self, from: file.data)
    }

    private func event(_ name: String) throws -> RelayEvent {
        let file = try #require(Self.fromRelay.first { $0.name == name + ".json" }, "no example \(name)")
        return try JSONDecoder().decode(RelayEvent.self, from: file.data)
    }

    @Test(arguments: toRelay)
    func aRequestIsWrittenAsItsExample(_ file: Vectors.File) throws {
        let request = try JSONDecoder().decode(RelayRequest.self, from: file.data)
        #expect(try JSONValue(writing: request) == JSONValue(json: file.data))
    }

    @Test(arguments: fromRelay)
    func anEventIsWrittenAsItsExample(_ file: Vectors.File) throws {
        let event = try JSONDecoder().decode(RelayEvent.self, from: file.data)
        #expect(try JSONValue(writing: event) == JSONValue(json: file.data))
    }

    @Test func requestsSayWhatTheExamplesSay() throws {
        let ama = "3f9c1e0a7b2d4c5e8f6a1b0c9d8e7f6a"
        let oware = RelayRequest.Game(name: "oware", protocolVersion: 1, formatVersion: 2)
        #expect(try request("create") == .create(game: oware, seats: 2, install: ama, proof: nil))
        #expect(try request("create-with-proof") == .create(
            game: oware, seats: 2, install: ama,
            proof: .init(store: "apple", transaction: "eyJhbGciOiJFUzI1NiJ9.e30.c2ln")))
        #expect(try request("create-ludo") == .create(
            game: .init(name: "ludo", protocolVersion: 1, formatVersion: 1), seats: 4, install: ama, proof: nil))
        #expect(try request("join") == .join(code: "K7M2QD", game: oware, install: "a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5"))
        #expect(try request("rejoin") == .rejoin(code: "K7M2QD", token: "Zk3vT8qLw2nR5xYc7bJ9mD4hF6gS1pA0"))
        #expect(try request("data-to-everyone")
            == .data(#"{"body":{"ping":{}},"protocolVersion":1,"sequence":16}"#, to: nil))
        #expect(try request("data-to-one")
            == .data(#"{"body":{"refused":{"_0":{"declined":{}}}},"protocolVersion":1,"sequence":5}"#, to: PeerID("p1")))
        #expect(try request("roll") == .roll)
        #expect(try request("leave") == .leave)
        #expect(try request("ping") == .ping)
        #expect(Self.toRelay.count == 10, "an example was added: say here what it means")
    }

    @Test func eventsSayWhatTheExamplesSay() throws {
        #expect(try event("room-created") == .room(
            code: "K7M2QD", peer: PeerID("p0"), token: "Hq2Wm8ZsX4vB6nK9tR3yL7cP5dG1jF0a", peers: []))
        #expect(try event("room-joined") == .room(
            code: "K7M2QD", peer: PeerID("p1"), token: "Zk3vT8qLw2nR5xYc7bJ9mD4hF6gS1pA0", peers: [PeerID("p0")]))
        #expect(try event("peer-joined") == .peer(PeerID("p1"), .joined))
        #expect(try event("peer-dropped") == .peer(PeerID("p1"), .dropped))
        #expect(try event("peer-left") == .peer(PeerID("p1"), .left))
        #expect(try event("data") == .data(#"{"body":{"ping":{}},"protocolVersion":1,"sequence":16}"#, from: PeerID("p0")))
        #expect(try event("rolled") == .rolled(n: 3, value: 6))
        #expect(try event("pong") == .pong)
        // `.other` stands for a reason this app does not know, so the relay never sends it.
        let reasons = RelayEvent.Refusal.allCases.filter { $0 != .other }
        for reason in reasons {
            #expect(try event("refused-\(reason.rawValue)") == .refused(reason))
        }
        #expect(Self.fromRelay.count == 8 + reasons.count, "an example was added: say here what it means")
    }

    /// A newer relay may say things this app has never heard of. They are passed over, not a crash
    /// and not a dropped connection.
    @Test func whatANewerRelaySaysIsPassedOver() throws {
        let news = Data(#"{"type":"turn","seat":2}"#.utf8)
        #expect(try JSONDecoder().decode(RelayEvent.self, from: news) == .unknown("turn"))
        let reason = Data(#"{"type":"refused","reason":"banned"}"#.utf8)
        #expect(try JSONDecoder().decode(RelayEvent.self, from: reason) == .refused(.other))
        let state = Data(#"{"type":"peer","peer":"p1","state":"watching"}"#.utf8)
        #expect(try JSONDecoder().decode(RelayEvent.self, from: state) == .unknown("peer"))
    }

    /// A room message rides inside `data` as its own JSON text, untouched.
    @Test func aRoomMessageRidesInsideData() throws {
        let envelope = Envelope(protocolVersion: 1, sequence: 7, body: RoomMessage<Tally, TallyIntent>.intent(.add(3)))
        let bytes = try JSONEncoder().encode(envelope)
        let request = try RelayRequest.data(bytes, to: nil)
        let wire = try JSONEncoder().encode(request)
        guard case let .data(text, to: nil) = try JSONDecoder().decode(RelayRequest.self, from: wire) else {
            Issue.record("not data")
            return
        }
        #expect(Data(text.utf8) == bytes)
        #expect(throws: RelayRequest.NotText.self) { try RelayRequest.data(Data([0xFF, 0xFE]), to: nil) }
    }
}

@Suite("Room codes")
struct RoomCodeTests {
    @Test func aCodeIsSixOfThirtyOneCharactersThatAreHardToConfuse() {
        #expect(RoomCode.alphabet.count == 31)
        for confusing in "0O1IL" { #expect(!RoomCode.alphabet.contains(confusing)) }
        #expect(RoomCode("K7M2QD")?.text == "K7M2QD")
    }

    @Test func typingIsForgiven() {
        #expect(RoomCode("k7m2qd")?.text == "K7M2QD")
        #expect(RoomCode(" k7m 2qd ")?.text == "K7M2QD")
        #expect(RoomCode("K7M-2QD")?.text == "K7M2QD")
    }

    @Test func anythingElseIsNotACode() {
        #expect(RoomCode("") == nil)
        #expect(RoomCode("K7M2Q") == nil)
        #expect(RoomCode("K7M2QDX") == nil)
        #expect(RoomCode("K7M2Q0") == nil, "0 is not used, so that it is never read as O")
        #expect(RoomCode("K7M2QL") == nil)
    }

    @Test func aCodeIsFoundInAJoinLink() {
        #expect(RoomCode(link: URL(string: "https://leluoware.com/lelu-oware/join/K7M2QD")!)?.text == "K7M2QD")
        #expect(RoomCode(link: URL(string: "https://leluoware.com/lelu-ludo/join/k7m2qd/")!)?.text == "K7M2QD")
        #expect(RoomCode(link: URL(string: "https://leluoware.com/lelu-oware/privacy")!) == nil)
        #expect(RoomCode(link: URL(string: "https://leluoware.com/join/K7M2QD/more")!) == nil)
    }

    @Test func readsAloudLetterByLetter() {
        #expect(RoomCode("K7M2QD")?.spelledOut == "K 7 M 2 Q D")
    }
}
