# Lelu Oware: nearby play (plan)

Two people, two phones, one game, with no router or internet. Phones find each other through
Bonjour over Apple's phone-to-phone Wi-Fi. **Free**, behind the `nearbyPlay` feature switch.

The design shared with Lelu Ludo is in [MULTIPLAYER.md](../../../docs/MULTIPLAYER.md): the layers,
MatchKit, feature switches, Apple requirements and the test pyramid. This file covers what is
specific to Oware and the order of work. Planned 2026-10-28. Progress: steps 1–5 built (2026-10-28/29); step 0 (two real phones) still to do.

**2026-10-30: the owner's review redesigns the screens.** Read [NEARBY_PLAY_REDESIGN.md](NEARBY_PLAY_REDESIGN.md)
first: one screen with no Host / Join, a Ready handshake, default names, reconnect and rejoin, and
the carved-wood kit in `art/nearby/`.

## What the player sees

1. **Home ▸ Play nearby**, a new tile, shown when `FeatureGate.isShown(Feature.nearbyPlay)`.
2. **Host a game** or **Join a game**.
   - **Host:** shows "Waiting for a player…", the rules from Settings (Abapa or Nam-Nam) and who
     starts (you, them or random).
   - **Join:** lists nearby games by host name ("Kofi's game · Abapa"). Tapping one asks the host.
3. **The host accepts** ("Ama wants to play"). The game starts on both phones.
4. **The game:**
   - Each phone shows **its own row nearest the player**. The guest's board is turned round, so
     north is at the bottom.
   - The other player's moves sow with the usual animation and sound. A small "Ama's turn" label
     shows whose turn it is.
   - Long-press previews work on your own turn.
   - **No undo and no hints** (GAME_PLAN §3.2: no undo online). There is Resign.
5. **The end:** the usual result screen, with **Rematch**. Both must tap it. The starter swaps.
6. **Connection lost:**
   - A banner reads "Reconnecting…" and the game waits.
   - After 60 s it offers **Finish against the computer**. Each phone holds the whole game, so
     either player can carry on alone from the same position.
   - Or **Leave**.
7. **Your name:** asked once, the first time you host or join ("What should nearby players call
   you?"). It is kept in Settings. iOS no longer gives apps the device's name.

Settings ▸ **Try nearby play** starts the demo: a pretend player on the same phone (MULTIPLAYER.md §5).

## How it fits the code

| Piece | Change |
|---|---|
| `OwareEngine/OnlineMatch.swift` | Renamed `OwareMatch` and kept as the match format for nearby and later online play. It gains `starter: Player` and a `matchID: UUID` for rejoining and rematches. Keep a `typealias OnlineMatch = OwareMatch` until callers move. Format version 2; version 1 data still decodes. |
| `OwareEngine` (new) | `OwareIntent`: `.play(house:)`, `.resign`, `.rematch`. Applying an intent to an `OwareMatch` returns the next match or a refusal. The host's rules, in the engine, and tested on Linux. |
| `packages/MatchKit` (new) | Shared transport, Room, `LoopbackTransport`, `MatchKitNearby` (MULTIPLAYER.md §2). |
| `SupportKit` | `Access` + `FeatureGate` (MULTIPLAYER.md §3). `OnlinePolicy` and its tests move here. |
| `Support/Features.swift` (new) | The app's table: `nearbyPlay: .free`, `online: .off`. It replaces `FeatureFlags.onlinePlay`. `FeatureFlags.newsletter` stays as it is. |
| `Game/GameMode.swift` | New `.remote(RemoteGame)`, where `RemoteGame` holds `mySide`, `opponentName` and `via` (`.nearby` now, `.online` later). `aiSide` stays nil; a new `remoteSide` is the other player's side. Not resumable after the app is closed in v1. |
| `Game/GameSession.swift` | Takes an optional `MatchLink`, the bridge to a Room. `humanToMove` is false on the remote side. `play(house:)` on your turn sends the intent and waits for the host's snapshot before animating. The host's own moves go through the same path, so both phones behave alike. Snapshots from the other side animate like computer moves today. `undo` and hints are off in `.remote`. |
| `Game/RemoteGame.swift` (new) | `MatchLink`: Room ⇄ session (start, snapshots, rematch, drop → offer the computer). |
| `Board/BoardScene.swift` | A `bottomSide: Player` setting, so the guest sees north nearest. |
| `Screens/NearbyView.swift` (new) | Host / Join / waiting room / name prompt / local-network help. |
| `Screens/GameView.swift` | Turn label, reconnect banner, Rematch. No Undo / Hint in `.remote`. |
| `Support/Analytics.swift` | `nearby.hosted`, `nearby.joined`, `nearby.finished` (outcome), `nearby.dropped`. No names are sent. |
| `project.yml` | `NSLocalNetworkUsageDescription`, `NSBonjourServices: [_leluoware._tcp]`. |
| `docs/lelu-oware/privacy.md`, `APP_STORE.md` | The nearby play paragraph, and the review note. |

When online play comes later:
- add `GameCenterTransport` to MatchKit;
- an "Online" tile that finds a game through Game Center;
- `via: .online`;
- switch `online` to `.unlock(...)` in `Features.swift`.

The match format, the intents, `MatchLink`, the board and the game screen are reused unchanged.

## Order of work: tests first

Each step is one PR with a Conventional Commit title. In each PR, the tests are committed first and
fail, then the code makes them pass. Everything stays hidden (`nearbyPlay: .off`) until step 6.

### Step 0: spike on two phones (throwaway branch, not merged)
A bare app with `NWListener` and `NWBrowser`, peer-to-peer on, on two iPhones.

It answers these questions:
- Do they connect with Wi-Fi on but joined to no network?
- In flight mode with Wi-Fi on?
- How fast is the first connection, and does it reconnect after the app is backgrounded?

Write the answers in this file. If peer-to-peer is unreliable, look at Wi-Fi Aware before step 3.

### Step 1: `feat(engine): an Oware match format for playing on two phones`
Tests first (`OwareEngineTests/OwareMatchTests.swift`):
- version 1 `OnlineMatch` JSON decodes as `OwareMatch`;
- a version 3 match is refused with `newerFormat`;
- `.play` on the wrong turn, from an empty house, or breaking the feeding rule is refused;
- `.resign` ends it for the other side;
- `.rematch` gives a fresh match with the other starter and a new `matchID`;
- a whole Nam-Nam game replays to the same state as `GameRecord`;
- a maximum-length game encodes under 64 KB;
- a snapshot is applied only if it extends the match the phone already has (stale ones are ignored).

Then: the rename, `OwareIntent`, `starter`, `matchID`.

**Built.** `OwareMatch` also has `game` (1, 2, 3… for rematches) so `supersedes(_:)` can tell a
rematch from an old game's late message. `starter` sets who sows first in round 1; later Nam-Nam
rounds still alternate as the engine already does.

### Step 2: `feat(supportkit): feature switches that can become paid`
Tests first (`SupportKitTests/FeatureGateTests.swift`):
- `.off` is not shown;
- `.free` is usable by everyone;
- `.unlock` is usable once purchased, or by founding players when included;
- host pays: an invited player can join;
- every `OnlinePolicy` test, ported.

The app adds `FeatureTableTests`, which lists `nearbyPlay: .free` and `online: .off`.

Then: `FeatureGate`, `Features.swift`, with `OnlineAccess` reading the gate.

**Built.** `OnlinePolicy`'s rules are now `Access.canUse` / `canJoin`. Nothing used `OnlineAccess`, so it
was removed rather than kept; `Feature.gate()` builds the app's gate. `nearbyPlay` is `.off` until step 6.

### Step 3: `feat(matchkit): rooms for playing on two phones`
Tests first (`MatchKitTests`, Linux):
- **Framer:** split and joined packets, a 64 KB limit, garbage input.
- **Envelope:** sequence ordering and repeats dropped.
- **Room on `LoopbackTransport`, joining:**
  - the host accepts or declines;
  - a second guest is refused with "room full" (Oware has 2 seats);
  - a newer protocol version is refused.
- **Room on `LoopbackTransport`, play:**
  - an intent from the guest reaches the host, and the host's snapshot reaches the guest;
  - a guest's snapshot is ignored.
- **Room on `LoopbackTransport`, connection:**
  - heartbeat: 6 s of silence marks the peer "reconnecting", and 60 s ends the seat. Time is injected
    (a test clock) so the tests run instantly;
  - rejoining within 60 s gets the same seat and the latest snapshot.

`MatchKitNearbyTests` (macOS): a host and a browser on one Mac find each other and exchange 100
messages in order.

Then: the package, CI callers through `reusable-swift-package.yml` (Linux for `MatchKit`, macOS for
the Nearby tests), and an entry in `MONOREPO.md`.

**Built.** `Room<Rules: RoomRules>` is a `@MainActor` class; heartbeats run from `tick()`, which
`startHeartbeat()` calls every 2 s and tests call by hand with a `ManualClock`. Rejoining uses a token
from the welcome (`reconnect(over:)` on the guest). `NearbyHost` / `NearbyBrowser` / `NearbyTransport`
in `MatchKitNearby`; the macOS test finds a host on the same Mac and sends 100 messages in order.

### Step 4: `feat(oware): play a game on two phones`, the session, with no screens yet
Tests first (`OwareTests/RemoteGameTests.swift`, two `GameSession`s joined by `LoopbackTransport`):
- the host moves and the guest's board matches;
- the guest moves and the host's board matches;
- you cannot move on the other player's turn;
- undo and hints are unavailable;
- resign ends both;
- a rematch needs both, and the starter swaps;
- dropping for 60 s offers the computer, and finishing against it is recorded as a normal game
  against the computer;
- both phones always show the same position (checked after every move of a full scripted game).

Then: `GameMode.remote`, `MatchLink`, the `GameSession` changes, and `BoardScene.bottomSide`.

**Built**, except `BoardScene.bottomSide`, which moves to step 5 with the screens. The room's match is
`OwareTable` (the `OwareMatch` plus who has asked for a rematch). `GameSession.canAgreeToStop` is
false on two phones, and "Stop here and count" should be hidden there in step 5. In Abapa, a move
that can feed nobody ends the game without sowing, so it is not counted in `moveNumber`.

### Step 5: `feat(oware): nearby play screens`
Tests first:
- **XCUITest `NearbyUITests` with `--nearby-demo`:**
  - Home ▸ Play nearby ▸ Host, the demo player joins, play to a scripted win, Rematch;
  - the guest's board is turned round;
  - reconnect banner: the demo goes quiet on cue.
- **Maestro:** `nearby-demo.yaml`.
- **Accessibility labels:** "Your turn", "Ama's turn", "Reconnecting".

Then:
- `NearbyView`, the `GameView` changes, the name prompt, the local-network help;
- Info.plist keys, analytics;
- Settings ▸ Try nearby play.

**Built.** `NearbyLobby` (Game/NearbyLobby.swift) runs Host / Join over a `NearbyNetwork`: the
live one wraps `NearbyHost` / `NearbyBrowser`, and `DemoNetwork` puts the demo player, Ama, on a
`LoopbackTransport`. Ama plays the first legal move two seconds after her turn comes, always agrees
to a rematch, and follows `--demo-resign-after=N` (first game only) and `--demo-quiet-after=N`
(twelve seconds of silence). `BoardLayout(size:bottomSide:)` turns the board round for the guest, so
the scene and the touch areas move together. Your name is kept under `nearbyName` and can be changed
in Settings. To try it on two phones in a Debug build before step 6, launch with `-nearbyPlay YES`
(or `--nearby`). Writing the demo found a MatchKit bug: a guest out of range missed the host's
moves and both phones then waited. The host now resends the match when a quiet seat is heard
again (`aGuestBackFromAQuietSpellCatchesUp`). `NearbyHost` and `NearbyBrowser` report
`NearbyStatus.localNetworkDenied`, and the Nearby screen then says how to turn Local Network on.

### Step 6: `feat(oware): turn on nearby play`
- `nearbyPlay: .free`;
- the privacy page and the App Review note;
- What's New text.

Real-phone checklist before TestFlight:
- [ ] Two iPhones, Wi-Fi on but joined to no network: host, join, a full game, rematch.
- [ ] The same in flight mode with Wi-Fi on, and on a shared home Wi-Fi.
- [ ] iPhone with iPad; the oldest iOS 17 device available.
- [ ] Local network permission declined, then the Settings help shown, allowed, and it works.
- [ ] Guest backgrounds the app for 20 s and comes back: same game. Walk out of range for 90 s:
      Finish against the computer works on both.
- [ ] Two games hosting side by side: each guest joins the right one.
- [ ] VoiceOver: whose turn, the other player's moves read out.

## Still to decide (later, not blocking)

- **Saved games:** decided 2026-10-30: no. A nearby game does not survive both apps being closed.
  (The `matchID` would make it possible later.)
- **Join code:** should joining need a 4-digit code shown on the host? Accepting each player is
  enough between friends. A code could also key encryption (TLS with a pre-shared key) if wanted.
- **Game Center:** decided 2026-10-30: no. Nearby wins earn no achievements or scores (easy to
  farm against a second phone of your own).
