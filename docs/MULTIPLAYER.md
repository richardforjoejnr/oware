# Playing together: shared design

How two or more phones play one game, for every app in this repository. Nearby play comes first
(Lelu Oware, then Lelu Ludo); online play comes later and must not need a rewrite. The per-app plans
are [Lelu Oware](../apps/lelu-oware/docs/NEARBY_PLAY.md) and
[Lelu Ludo](../apps/lelu-ludo/docs/NEARBY_PLAY.md). Owner decisions, 2026-10-28:

| Decision | Choice |
|---|---|
| How phones find each other | Apple's phone-to-phone Wi-Fi, found through Bonjour (Network framework with peer-to-peer on). No router or internet; Wi-Fi and Bluetooth must be on. |
| Order | Lelu Oware first, then Lelu Ludo (2–4 phones) |
| Price | Nearby play is **free**. Every feature still goes through a switch, so any of them can be made paid later. |
| Empty seats (Ludo) | Played by the computer |
| Later | Online play (Game Center), paid, host pays (`apps/lelu-oware/docs/SERVICES.md` §8) |
| Way of working | Tests first: each step's tests are written, and fail, before its code |

## 1. Why Network framework, not Bluetooth or Multipeer

- **Multipeer Connectivity** is deprecated: `MCSession` is marked deprecated in iOS 27, and Apple's
  technote TN3213 says to move to Network framework.
- **Core Bluetooth** is slow and fiddly to build on, and awkward with more than two phones.
- **Network framework**: `NWListener` (host) and `NWBrowser` (find games), with Bonjour and
  `includePeerToPeer = true`, use Apple's phone-to-phone Wi-Fi when there is no shared network.
  This is the same link Multipeer used. It works on iOS 17, the apps' minimum. The newer
  `NetworkConnection` API is iOS 26 only; move to it when the minimum is raised.
- **Wi-Fi Aware** (iPhone 12 and later) is an alternative for pairing if peer-to-peer proves flaky.
  It is not needed to start.

## 2. Layers

The game never talks to the network directly. Each layer only knows the one below it, so online
play means **one new transport** and new screens for finding a game. The rules, the match format,
the host logic and the game screen stay as they are.

```
 Screens        Host / Join / Waiting room / Game           (per app)
 Session        GameSession / LudoSession: a "remote" seat  (per app)
 Match          OwareMatch / LudoMatch: rules + moves, replayed by the engine (engine packages)
 Room           MatchKit.Room: seats, host checks, snapshots, rejoin  (shared, pure Swift)
 Transport      MatchTransport protocol                     (shared)
                ├── NearbyTransport   Network framework, Bonjour, peer-to-peer   ← now
                ├── LoopbackTransport in memory, for tests and UI tests         ← now
                └── GameCenterTransport GKMatch / GKTurnBasedMatch              ← later
```

### Transport (`packages/MatchKit`)

```swift
public struct PeerID: Hashable, Sendable, Codable { public let raw: String }

public enum TransportEvent: Sendable {
    case connected(PeerID)      // names come in the room's hello, not from the transport
    case disconnected(PeerID)
    case received(Data, from: PeerID)
}

public protocol MatchTransport: AnyObject, Sendable {
    var me: PeerID { get }
    var events: AsyncStream<TransportEvent> { get }
    /// To one peer, or everyone when `to` is nil.
    func send(_ data: Data, to peer: PeerID?) async throws
    func close()
}
```

Finding a game is separate from the transport, because nearby and online find games differently:
- **Nearby:** `NearbyHost` advertises a Bonjour service; `NearbyBrowser` lists the games around you.
- **Online (later):** Game Center invites and matchmaking.

Both end up with a `MatchTransport`.

### Room (`MatchKit.Room`, pure Swift, tested on Linux)

The **host is in charge**. Guests send *intents* ("play house 4", "roll", "move token 2"). The host
checks each one with the engine. If it is legal, the host sends everyone a *snapshot* of the whole
match, and every phone replays the snapshot through its own engine before showing it. A snapshot is
the full match, so:
- a phone that rejoins, or missed a message, is up to date after one snapshot;
- Game Center turn-based play (later) needs no change: its "match data" is the same snapshot;
- a tampered or out-of-date message is refused by the replay, as `OnlineMatch` already does.

Every message is wrapped in an envelope:

```swift
public struct Envelope<Body: Codable & Sendable>: Codable, Sendable {
    public var protocolVersion: Int   // a phone refuses newer versions and says "update the app"
    public var sequence: Int          // per sender, so repeats and stale messages are dropped
    public var body: Body
}

public enum RoomMessage<Match: Codable & Sendable, Intent: Codable & Sendable>: Codable, Sendable {
    case hello(name: String, rejoin: UUID?)   // rejoin: the token from an earlier welcome
    case welcome(seat: Int, token: UUID, names: [Int: String], snapshot: Match)
    case refused(Refusal)             // room full, game started, newer version, host said no
    case intent(Intent)
    case snapshot(Match)
    case ping, bye
}
```

Room behaviour, all tested with `LoopbackTransport`:
- **Joining:** the host accepts or declines each person ("Ama wants to join").
- **Messages:** a framed message is at most 64 KB (Game Center's turn-based limit, so online fits).
- **Heartbeat:** a ping every 2 s. A peer silent for 6 s is shown as "reconnecting".
- **Rejoining:** a peer gone for 60 s loses its seat. If it comes back in time it gets the same seat.
  A seat heard again after a quiet spell is sent the match as it stands, since it may have missed moves.
- **Leaving:** a peer that says `bye` is reported as `left(seat:)` at once, not as `seatLost`, so the
  app can say "Richard left the game" rather than wait for a connection to come back.
- **Starting (each game's rules):** connected is not started. In Oware the `OwareTable` holds a
  `ready` set: each phone sends `ready(stateHash:)` with the fingerprint of the opening as its own
  engine replays it, and the host refuses moves until both match (`GameState.fingerprint`).
- **Who decides:** only the host's phone decides. A guest's own engine never moves the game on.
  It only checks what the host sends.

Messages over TCP are framed with a 4-byte length prefix. The framer is pure Swift and tested on
Linux. Everything that imports `Network` sits behind `#if canImport(Network)`, so `swift test`
still runs in the Linux CI job.

### Package layout

```
packages/MatchKit/
  Sources/MatchKit/            Transport protocol, Envelope, Room, Framer, LoopbackTransport (pure)
  Sources/MatchKitNearby/      NearbyHost, NearbyBrowser, NearbyTransport (#if canImport(Network))
  Tests/MatchKitTests/         Linux + macOS
  Tests/MatchKitNearbyTests/   macOS only: two transports on localhost
```

The match formats stay in the engines, beside the rules they replay:
- `OwareMatch` grows out of today's `OnlineMatch`;
- `LudoMatch` is new.

MatchKit is generic over them and knows nothing about Oware or Ludo.

## 3. Feature switches (paid later)

Today: `FeatureFlags` (on/off) and `OnlinePolicy` (host pays), both in Lelu Oware only. They become
one shared switchboard in SupportKit, which both apps use:

```swift
public enum Access: Sendable, Equatable {
    case off                                  // built, not shown
    case free
    case unlock(productID: String, hostPays: Bool, foundingIncluded: Bool)
}

@MainActor @Observable
public final class FeatureGate {
    public init(_ table: [String: Access], unlocks: [String: Unlock], founding: FoundingPlayer)
    public func isShown(_ feature: String) -> Bool        // off → false
    public func canUse(_ feature: String) -> Bool         // free, purchased, or founding
    public func canJoin(_ feature: String, invitedByHostWhoCanUse: Bool) -> Bool
}
```

Each app keeps its own table in one file, for example in Lelu Oware:

```swift
enum Feature {
    static let nearbyPlay = "nearbyPlay"
    static let online = "online"
    static let table: [String: Access] = [
        nearbyPlay: .free,
        online: .off,      // later: .unlock(productID: "com.richardforjoe.oware.online", hostPays: true, foundingIncluded: false)
    ]
}
```

- Making a feature paid is a one-line change in that table, plus the product in App Store Connect.
- Screens only ask `canUse` / `canJoin`, so no screen changes.
- Smaller parts of a feature can get their own entry if they might be sold separately later. One
  example is `nearbyFourPlayers` in Ludo (free now).
- The table is tested: a test lists every feature and its expected access, so changing a price is
  a deliberate change to a test.
- `OnlinePolicy`'s rules (host pays, founding players) move into `FeatureGate` with their tests.

## 4. Apple requirements (both apps)

- **Info.plist (per app):**
  - `NSLocalNetworkUsageDescription`: "Lelu Oware looks for players near you so you can play on two
    phones."
  - `NSBonjourServices`: `_leluoware._tcp` (Lelu Ludo: `_leluludo._tcp`).
- **The prompt:** iOS asks about the local network the first time a phone hosts or looks for games.
  If the player says no, the screen explains how to allow it in Settings.
- **Privacy:** moves go phone to phone and nothing goes to a server, so the App Privacy answers
  stay as they are. The privacy page gains one paragraph on nearby play.
- **App Review:** the review notes say that nearby play needs two devices. They also explain that
  a reviewer can try it alone using the in-app demo (§5).

## 5. Testing (the pyramid, for both apps)

| Layer | What | Where it runs |
|---|---|---|
| Engine | Match replay, refusing illegal or tampered moves, the version check, size under 64 KB | Linux CI |
| MatchKit | Framer, envelopes, Room (join, refuse, full, heartbeat, rejoin, host leaves), on `LoopbackTransport` | Linux CI |
| MatchKitNearby | Two `NearbyTransport`s on one Mac find each other and exchange a match | macOS CI |
| App | Session with a remote seat over `LoopbackTransport`: turns, resign, rematch, drop → computer | Simulator (CI) |
| UI | `--nearby-demo`: a loopback opponent in the same app plays scripted moves, so XCUITest and Maestro can go Host → game → result on one simulator | Simulator (CI) |
| Real phones | A written checklist per app (in its plan) | By hand, before each TestFlight |

`--nearby-demo` also ships in Settings ▸ "Try nearby play" for App Review, and for players who want
to see it before finding a friend.
