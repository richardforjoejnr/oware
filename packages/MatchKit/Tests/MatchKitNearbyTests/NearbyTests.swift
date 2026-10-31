#if canImport(Network)
import Foundation
import Testing
import MatchKit
@testable import MatchKitNearby
import Network

/// A host and a browser on one Mac find each other over Bonjour and talk.
@Suite("Nearby transport on this Mac", .timeLimit(.minutes(1)))
struct NearbyTests {
    @Test func aHostIsFoundAndAHundredMessagesArriveInOrder() async throws {
        let serviceType = "_matchkittest._tcp"
        let gameName = "Test \(UUID().uuidString.prefix(8))"
        let host = try NearbyHost(serviceType: serviceType, name: gameName, info: ["rules": "abapa"])
        defer { host.close() }

        let browser = NearbyBrowser(serviceType: serviceType)
        defer { browser.stop() }
        var found: NearbyGame?
        for await games in browser.games {
            if let game = games.first(where: { $0.name == gameName }) { found = game; break }
        }
        let game = try #require(found)
        #expect(game.info["rules"] == "abapa")

        let guest = browser.connect(to: game)
        defer { guest.close() }

        // The host sees the guest arrive.
        var guestPeer: PeerID?
        var hostEvents = host.events.makeAsyncIterator()
        while guestPeer == nil, let event = await hostEvents.next() {
            if case let .connected(peer) = event { guestPeer = peer }
        }
        var guestEvents = guest.events.makeAsyncIterator()
        var hostPeer: PeerID?
        while hostPeer == nil, let event = await guestEvents.next() {
            if case let .connected(peer) = event { hostPeer = peer }
        }

        for i in 0..<100 { try await guest.send(Data("move \(i)".utf8), to: nil) }
        var received: [String] = []
        while received.count < 100, let event = await hostEvents.next() {
            if case let .received(data, from) = event, from == guestPeer { received.append(String(decoding: data, as: UTF8.self)) }
        }
        #expect(received == (0..<100).map { "move \($0)" })

        // And back the other way, with a message near the 64 KB limit.
        let big = Data(repeating: 7, count: 60_000)
        try await host.send(big, to: guestPeer)
        var echoed: Data?
        while echoed == nil, let event = await guestEvents.next() {
            if case let .received(data, _) = event { echoed = data }
        }
        #expect(echoed == big)

        // Closing one end is seen by the other.
        guest.close()
        var left = false
        while !left, let event = await hostEvents.next() {
            if case .disconnected(guestPeer!) = event { left = true }
        }
        #expect(left)
    }

    /// Once the game has started the host stays findable, marked as started so the list can leave
    /// it out, and a guest whose connection broke can connect again to take its seat back.
    @Test func aStartedGameCanBeConnectedToAgain() async throws {
        let serviceType = "_matchkittest._tcp"
        let gameName = "Rejoin \(UUID().uuidString.prefix(8))"
        let host = try NearbyHost(serviceType: serviceType, name: gameName, info: ["rules": "abapa"])
        defer { host.close() }
        let browser = NearbyBrowser(serviceType: serviceType)
        defer { browser.stop() }
        var games = browser.games.makeAsyncIterator()
        var found: NearbyGame?
        while found == nil, let list = await games.next() { found = list.first { $0.name == gameName } }
        let game = try #require(found)

        var hostEvents = host.events.makeAsyncIterator()
        let first = NearbyTransport.connect(to: game)
        var connections = 0
        while connections < 1, let event = await hostEvents.next() { if case .connected = event { connections += 1 } }

        host.markStarted()
        var marked: NearbyGame?
        while marked == nil, let list = await games.next() {
            marked = list.first { $0.name == gameName && $0.info["started"] == "1" }
        }
        #expect(marked?.info["rules"] == "abapa", "the rest of the listing is kept")

        first.close()   // the guest's app went to the background
        let again = NearbyTransport.connect(to: try #require(marked))
        defer { again.close() }
        while connections < 2, let event = await hostEvents.next() { if case .connected = event { connections += 1 } }
        #expect(connections == 2, "the host takes the guest back")
    }

    /// Bonjour's "policy denied" is the Local Network permission being off; the app then shows
    /// how to turn it on rather than an empty list.
    @Test func aDeniedPermissionIsToldApartFromOtherFailures() {
        #expect(NearbyStatus(.dns(-65570)) == .localNetworkDenied)
        #expect(NearbyStatus(.dns(-65537)) == .failed)
        #expect(NearbyStatus(.posix(.ECONNREFUSED)) == .failed)
        #expect(NearbyStatus(NWBrowser.State.ready) == .working)
        #expect(NearbyStatus(NWBrowser.State.waiting(.dns(-65570))) == .localNetworkDenied)
        #expect(NearbyStatus(NWListener.State.ready) == .working)
    }
}
#endif
