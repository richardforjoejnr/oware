import Foundation
import Testing
@testable import MatchKit

@Suite("Messages over a stream: a 4-byte length, then the message")
struct FramerTests {
    @Test func oneMessageRoundTrips() throws {
        var reader = Framer.Reader()
        let message = Data("play house 4".utf8)
        #expect(try reader.push(Framer.frame(message)) == [message])
    }

    @Test func aMessageSplitAcrossPacketsIsJoined() throws {
        var reader = Framer.Reader()
        let message = Data((0..<1_000).map { UInt8($0 % 251) })
        let framed = try Framer.frame(message)
        var out: [Data] = []
        // One byte at a time: the worst a stream can do.
        for byte in framed { out += try reader.push(Data([byte])) }
        #expect(out == [message])
    }

    @Test func severalMessagesInOnePacketAreSplit() throws {
        var reader = Framer.Reader()
        let messages = ["a", "", "ccc", String(repeating: "d", count: 300)].map { Data($0.utf8) }
        var packet = Data()
        for m in messages { packet += try Framer.frame(m) }
        // Cut the stream at an awkward place, mid-length and mid-body.
        let cut = 6
        let first = try reader.push(packet.prefix(cut))
        let rest = try reader.push(packet.dropFirst(cut))
        #expect(first + rest == messages)
    }

    @Test func messagesOver64KBAreRefused() throws {
        #expect(throws: Framer.Failure.tooLarge(Framer.maxMessageBytes + 1)) {
            try Framer.frame(Data(count: Framer.maxMessageBytes + 1))
        }
        #expect(try Framer.frame(Data(count: Framer.maxMessageBytes)).count == Framer.maxMessageBytes + 4)
    }

    @Test func garbageIsRefusedNotBuffered() throws {
        var reader = Framer.Reader()
        // A length far beyond the limit: a broken or hostile sender. Refuse rather than wait for 4 GB.
        #expect(throws: Framer.Failure.tooLarge(0xFFFF_FFFF)) { try reader.push(Data([0xFF, 0xFF, 0xFF, 0xFF, 1, 2])) }
    }
}

@Suite("Envelopes: versions and the order of messages")
struct EnvelopeTests {
    @Test func sequencesOnlyMoveForwardPerSender() {
        var filter = SequenceFilter()
        let a = PeerID("a"), b = PeerID("b")
        #expect(filter.accept(1, from: a))
        #expect(filter.accept(2, from: a))
        #expect(!filter.accept(2, from: a), "a repeat is dropped")
        #expect(!filter.accept(1, from: a), "a late message is dropped")
        #expect(filter.accept(1, from: b), "each sender counts on its own")
        #expect(filter.accept(5, from: a), "a gap is fine: the next snapshot carries everything")
        filter.forget(a)
        #expect(filter.accept(1, from: a), "a peer that starts again is heard again")
    }

    @Test func anEnvelopeRoundTrips() throws {
        let envelope = Envelope(protocolVersion: MatchKit.protocolVersion, sequence: 3, body: "hello")
        let data = try JSONEncoder().encode(envelope)
        #expect(try JSONDecoder().decode(Envelope<String>.self, from: data) == envelope)
        #expect(try JSONDecoder().decode(EnvelopeHeader.self, from: data).protocolVersion == MatchKit.protocolVersion)
    }
}
