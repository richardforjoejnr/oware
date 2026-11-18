# Playing online: plan

How two to four phones in different places play one game, for every app in this repository, with
a small backend on AWS. Planned 2026-11-15; what is built and deployed since is in
[Lelu Oware's STATUS.md](../apps/lelu-oware/docs/STATUS.md) ▸ Online play, and the owner's
decisions of 2026-11-18 (links first, rematch, play again, Quick Match put off) are in §12 and
§14. It builds on [MULTIPLAYER.md](MULTIPLAYER.md) (the layers, MatchKit,
feature switches) and on the nearby play work in
[Lelu Oware](../apps/lelu-oware/docs/NEARBY_PLAY_REDESIGN.md). Per-app notes:
[Lelu Oware](../apps/lelu-oware/docs/ONLINE_PLAY.md), [Lelu Ludo](../apps/lelu-ludo/docs/ONLINE_PLAY.md).

Where this plan changes an earlier decision, it says so in §2.

## 1. The four questions

| Question | Recommendation | Main reason |
|---|---|---|
| Friends only, or play with anyone? | **Friends only first**: start a game, share a 6-letter code or a link. Playing with anyone comes last (§3). | An invite room needs no accounts, no moderation and no waiting room that sits empty. Open matchmaking needs all three, plus report and block for App Review. |
| Ludo first, or Oware? | **Oware first**, with the server built for 2–4 seats from the first day (§4). | Oware's match format, room rules, session, lobby, Ready handshake and reconnect are built and tested. Ludo has no match format yet and nothing of nearby play. |
| Where does the backend live? | **In the AWS repo**, as one new app `apps/lelu-play`, serving **both games** (§9). | That repo already has the template, deploy scripts, preview environments and test rules for exactly this kind of app. One relay that knows nothing about either game is one thing to run, as MatchKit is one package. |
| What does it cost? | **Nothing when nobody plays.** About **US$0.001 per Oware game** and **US$0.01 per 4-phone Ludo game** (§8). | API Gateway WebSocket + Lambda + DynamoDB on-demand are all pay-per-use. No server, database instance, NAT, load balancer, firewall or paid key sits idle. |

In one sentence: add **one new transport** to MatchKit that talks to a small **relay** on AWS, keep
one phone in charge of the game exactly as in nearby play, and reuse the nearby lobby with a code
in place of "games nearby".

## 2. Earlier decisions: kept and changed

| Earlier decision | Where | This plan |
|---|---|---|
| Online play means one new transport; rules, match format, host logic and game screen stay | MULTIPLAYER.md §2 | **Kept.** This is the whole design. |
| Online is behind `FeatureGate`; one-time unlock; the host pays; invited friends play free | SERVICES.md §1, `Feature.table` | **Kept. Decided 2026-11-15: free at first, built so that switching to paid is one line** (§5, *Free now, paid later*): start as `.free`, then `.unlock(hostPays: true, …)`. Tips cannot be sold yet either (Paid Apps Agreement), so paid online could not ship today anyway. |
| No accounts; Game Center is the only sign-in and optional | SERVICES.md §1 | **Kept.** No sign-in for friends-only play (§6). |
| No adverts; worldwide audience | SERVICES.md §1 | **Kept.** |
| Online goes through **Game Center** (`GameCenterTransport`, `GKTurnBasedMatch`) | MULTIPLAYER.md, NEARBY_PLAY.md, SERVICES.md §8 | **Changed: AWS instead. This plan replaces SERVICES.md §8's "still to build" list.** Game Center is free but Apple-only, and an Android version is planned (PR #112). It also needs every player signed in to Game Center, which is off in the app today (`FeatureFlags.gameCenter = false`). |
| Messages at most 64 KB (Game Center's limit) | MULTIPLAYER.md §2 | **Tightened to 32 KB** for online: API Gateway bills in 32 KB steps and closes a connection on a larger frame. An Oware match is under 1 KB; a long Ludo match needs watching (§4). |
| A game does not survive both apps being closed; no undo, no hints | NEARBY_PLAY_REDESIGN.md decision 7 | **Changed for online (owner, 2026-11-15): an online game survives the app being closed**, because players are on phone networks that cut out. Each phone saves the game and can rejoin for 24 hours (§5, *A game that survives the app closing*). Nearby play keeps decision 7. No undo and no hints, as before. "Your turn" notifications are still a later stage (§11, stage 9). |
| Once the computer takes over, the game stays against the computer | NEARBY_PLAY_REDESIGN.md decision 2 | **Kept.** |

## 3. Friends only first

### What an invite room avoids

| | Invite by code or link | Play with anyone |
|---|---|---|
| Accounts | None | None strictly, but bans need an identity that is hard to throw away |
| Who you meet | Someone you sent the code to | A stranger |
| Names | Seen by a friend. The creator can turn someone away (**Not now**, already built) | Seen by strangers, so names become user-generated content: App Review 1.2 asks for a filter, a way to report, a way to block and a published contact |
| Chat | None | None. "Random or anonymous chat" apps are removed from the store (1.2). Fixed phrases at most |
| Children | The app is for all ages; a child only meets someone who was given the code | A child can meet any adult. Needs thought about age rating answers and children's privacy law, even with no chat |
| Empty rooms | Cannot happen: both players arrive together | With few players, "Find a game" waits and finds nobody. Needs a computer opponent as fallback, or it reads as broken |
| Cheating | Pointless between friends. Each phone already replays every move through its own rules | Worth someone's effort once there are rankings. Needs the server to referee (§7) |
| Ongoing work | None | Reading reports and answering them "in a timely way", for as long as the feature is on |
| Server work | A relay (§5) | The relay, plus a waiting queue, a referee, bans |

### Order

1. **Oware with a friend**: code and link. (Stages 1–6.)
2. **Ludo with friends**: 2–4 phones, the server rolls the dice. (Stage 7.)
3. **The server referees** every move. Needed before anything below. (Stage 8.)
4. **Games that last days**, with "your turn" notifications. (Stage 9.)
5. **Play with anyone**: quick match, fixed or filtered names, report and block, the computer steps
   in when nobody is waiting. Rankings only after that. (Stage 10.)

"Friends can find each other" (a friends list) is not on the list on purpose. It needs accounts, and
a link sent over WhatsApp does the same job. A **Play again with Ama** shortcut can be kept on the
phone alone.

## 4. Oware first

What exists, checked in the repository on 2026-11-15:

| Piece | Lelu Oware | Lelu Ludo |
|---|---|---|
| Rules engine, pure Swift, tested on Linux | `OwareEngine` | `LudoEngine` |
| Match format replayed by the engine | `OwareMatch`, `OwareIntent`, `GameState.fingerprint` | Not built (`LudoMatch` is step 1 of its nearby plan) |
| Room rules for MatchKit | `OwareTable`, `OwareRoomRules` (Ready handshake, rematch, paces) | Not built |
| Session with a remote seat | `GameSession` + `MatchLink`, tested over `LoopbackTransport` | Not built (`LudoSession` has no `MatchLink`) |
| Lobby and screens | `NearbyLobby`, Ready to play, reconnect; live for everyone (`nearbyPlay: .free`) | Not built |
| Still open in nearby play | Connection lost sheet, Rejoin card, the carved kit (redesign steps 3–4) | Everything: steps 1–5 |

"If four works, two is easy" is true of the **shared** parts, and those are already written for any
number of seats: `Room` takes `seatCount` from the game's rules, and `MatchTransport.send` goes to
one peer or everyone. So the plan gets the same benefit a cheaper way:

- the relay takes rooms of 2–4 seats from its first PR, and its tests run a **four-client room**
  before any Ludo screen exists;
- Oware is the first game through it, because its client side is done;
- Ludo online follows Ludo nearby steps 1–3 (match format, seats, session), which it needs anyway.

What Ludo adds, and where each is handled:

| Ludo needs | Answer |
|---|---|
| Dice nobody can fake | The **server rolls** (§7). A numbered roll goes to every phone; the match must use the rolls in order. |
| Empty seats played by the computer | The moves are chosen on the creator's phone, as in the nearby plan, but **the server rolls for computer seats too** (owner, 2026-11-15): every roll in an online game is a numbered server roll. The computer's moves go to the server with the referee (stage 8). |
| Someone leaves mid-game | The computer takes the seat after the waiting time; they can take it back (Ludo nearby plan). |
| The creator leaves | First version: as nearby, each guest can finish against computers. Fixed properly by the referee (stage 8), where no phone is in charge. |
| Bigger messages | A match is the full list of rolls and moves, so it grows. Keep it under 32 KB (test in `LudoMatchTests`); if a long game gets close, send only the new actions. |

## 5. How it works

### Layers

```
 Screens        Online lobby: Start game / Enter code / Ready / Game       (per app, reuses nearby)
 Session        GameSession + MatchLink, RemoteGame.via = .online          (built)
 Match          OwareMatch / LudoMatch, replayed by the engine             (built / Ludo to build)
 Room           MatchKit.Room: seats, host checks, snapshots, rejoin       (built)
 Transport      MatchTransport
                ├── NearbyTransport    Bonjour, peer-to-peer               (built)
                ├── LoopbackTransport  tests and demos                     (built)
                └── OnlineTransport    WebSocket to the relay              ← new (MatchKitOnline)

 ───────────────────────────── internet (wss://play.leluoware.com) ─────────────────────────────

 AWS, one app (apps/lelu-play in the AWS repo), us-east-1
   API Gateway WebSocket API ──▶ Lambda (Node 20, TypeScript) ──▶ DynamoDB on-demand, TTL on every item
        $connect / $disconnect / $default        rooms, seats, relay, dice        rooms, seats, connections, limits
   CloudWatch logs (short retention) · alarms · AWS Budget → email · an off switch (SSM parameter)
```

The **relay** does four things: makes rooms with a code, lets phones into a room, passes messages
between the phones in a room, and tells them when one joins or drops. It does not know the rules
of either game. For Ludo it also rolls dice.

One phone stays in charge of the game (the creator, seat 0), exactly as in nearby play. So `Room`,
the Ready handshake, the state hash, rematch and the "left the game" path all work as they do now.
`OnlineTransport` only has to turn relay messages into the three events a transport gives:
`connected`, `disconnected`, `received`.

### Messages

The room protocol (`hello`, `welcome`, `intent`, `snapshot`, `ping`, `bye`) is unchanged and rides
inside `data`. Around it, the relay speaks a small JSON format, version 1:

| Phone → relay | Relay → phone |
|---|---|
| `create {game, protocol, seats, install, proof?}` | `room {code, peer, token, peers}` |
| `join {code, install}` | `peer {peer, state: joined / left / dropped}` |
| `rejoin {code, token}` | `data {from, data}` |
| `data {to?, data}` | `rolled {n, value}` (Ludo) |
| `roll` (Ludo) | `refused {reason: notFound / full / paused / needsUpdate / needsUnlock / tooMany}` |
| `leave` | `pong` |
| `ping` | |

**Pin the room protocol first.** Today its JSON is whatever Swift's automatic `Codable` writes for
`Envelope`, `RoomMessage`, `OwareTable`, `TableIntent` and `OwareMatch`, and no test fixes it. That
is fine while both ends are the same Swift code. Before a server or an Android app reads it, every
message gets a JSON example in `shared/vectors/room-v1/` and a test that the app still writes and
reads exactly that. Where the automatic form is awkward for other languages (enum cases as nested
objects, dictionaries with non-text keys written as lists), fix it once, as room protocol
version 2, before anything else depends on it. This is stage 1.

### One game, from start to finish

```
 Ama's phone                         relay                          Kofi's phone
 ───────────                         ─────                          ────────────
 Start game
   connect, create ───────────────▶  makes room K7M2QD
   ◀──────────────── room(code, token)
   shows the code and Share
   (link: leluoware.com/lelu-oware/join/K7M2QD)       taps the link, or types the code
                                     ◀─────────────── connect, join(K7M2QD)
   ◀──────────────── peer(joined)    room(token) ───────────────▶
   ◀══ hello("Kofi") ════════════════════════════════════════════   (room protocol, inside data)
   "Kofi wants to play"  Ready / Not now
   ══ welcome(seat 1, snapshot) ════════════════════════════════▶   replays the opening
   Ready ══ ready(hash) ═▶ (own room)      ◀══ intent ready(hash) ═  Ready
   ══ snapshot (both ready) ════════════════════════════════════▶   game starts

   plays house 4: applies it, ══ snapshot ══════════════════════▶   replays, animates
   ◀══ intent play(house 9) ═════════════════════════════════════   plays house 9
   checks it with the engine, ══ snapshot ══════════════════════▶

                                                                    walks into a lift: link dies
   ◀──────────────── peer(dropped)   ($disconnect, or pings stop)
   "Reconnecting to Kofi…"                                          back on the network
                                     ◀─────────────── connect, rejoin(code, token)
   ◀──────────────── peer(joined)    room(same peer) ───────────▶
   ◀══ hello(rejoin) ════════════════════════════════════════════
   ══ welcome(same seat, snapshot) ═════════════════════════════▶   compares hash, carries on

   last move ══ snapshot (game over) ═══════════════════════════▶   result screen
   Rematch (both) → a new game in the same room, or
   leave ─────────────────────────▶  peer(left) ────────────────▶   "Ama left the game"
                                     room items expire by TTL
```

### Connections

- **Two hours at most.** API Gateway closes every WebSocket after 2 hours. The phone reconnects
  with `rejoin` and its token, the same path as a dropped link, so the player sees nothing.
- **Ten minutes idle.** A quiet connection is closed after 10 minutes. The room's own pings keep it
  open during a game.
- **App in the background.** iOS suspends the app and the socket dies within seconds. On return
  the phone rejoins and gets the snapshot. No background mode is asked for.
- **Timings.** Nearby play pings every 2 s, shows "Reconnecting…" after 4 s and gives up after 15 s.
  Mobile data is slower to come back and every ping costs a little, so online needs its own
  numbers: proposed ping every 10 s, "Reconnecting…" after 25 s, the sheet after 90 s (§12).
  `Room`'s three timings become a value passed in, so each transport sets its own.
- **Knowing your own link is down.** WebSocket ping frames are free on API Gateway and are answered
  by the gateway, so the phone can check its own link every few seconds without cost.
- **Different versions.** `create` carries the game, the room protocol version and the match format
  version. A phone that joins with other numbers gets `refused(needsUpdate)` and the existing
  "Update Lelu Oware on both phones" message. The relay's own format has a version too; the relay
  serves the last two.

### A game that survives the app closing

Decided by the owner on 2026-11-15: players are on phone networks, a link can be gone for minutes,
and iOS may close the app meanwhile. The game must still be there.

This does not need the referee (stage 8). One phone stays in charge, and both phones remember:

- **Each phone saves the online game to disk** after every snapshot: the room code, its seat
  token (in the Keychain), its seat, and the match so far. The save is removed when the game ends
  or the player leaves.
- **On launch, a saved game shows a Rejoin card on Home** (*Your game with Kofi* · **Rejoin** ·
  *Leave game*), the card nearby play's redesign already draws. Rejoin connects, sends
  `rejoin(code, token)` and carries on from the saved match. The join link does the same.
- **The relay keeps a playing room for 24 hours after its last message** (it was 2 hours). Seat
  tokens live as long as the room. Nothing more is stored: still no moves and no names on the
  server (§9).
- **Who can carry on:**

  | Who closed the app | What happens |
  |---|---|
  | The guest | The creator sees *Reconnecting to Kofi…*, then the sheet (*Keep waiting / Play the computer / Leave*). Keep waiting holds the seat; when Kofi rejoins he gets the snapshot and play goes on. |
  | The creator | The guest sees the same sheet. When the creator's phone returns it loads its saved match, rejoins as seat 0 and is in charge again. |
  | Both | Whoever returns first waits in the room. The game goes on when the creator is back, since the creator's phone applies the moves. Both saved matches are compared by hash on rejoin; if they differ the longer one that replays cleanly wins. |
  | The creator never returns | The guest can finish against the computer, as in nearby play. This is the one gap, and the referee (stage 8) closes it: then no phone is in charge. |

- **"Give up after 90 s" no longer ends anything.** It is when the sheet appears. The game is
  only over when someone chooses *Play the computer* or *Leave*, or the room expires.
- **No notifications yet.** A player who closed the app is not told it is their turn; they see the
  Rejoin card next time they open it. Stage 9 adds the notification.

Cost: a room item kept for a day is a few hundred bytes; nothing measurable. Work: about 2–3 days
across stages 4 and 5, with tests that kill and relaunch the app mid-game.

### Free now, paid later

Decided by the owner on 2026-11-15: online play is free at first and must be easy to switch to
paid. So the paid path is built and tested now and left switched off:

- **In the app** the switch is one line: `Feature.online` from `.free` to
  `.unlock(hostPays: true, …)` in `Feature.table`. Stage 5 builds *Start game* against
  `FeatureGate`, with unit and UI tests run in both settings, so the paywall, the host-pays rule
  (a guest with a code never pays) and founding players are proven before they are needed.
- **On the relay**, `create` has an optional `proof` field from version 1: the signed StoreKit
  transaction for the unlock. A stage setting `requireProof` (an SSM parameter, like the off
  switch) is `false` to start. When it is turned on, a `create` without a valid proof gets
  `refused(needsUnlock)`. Old app versions keep working until then, and no protocol change is
  needed on the day. `join` never needs a proof.
- **What the switch still takes:** the product approved in App Store Connect (which needs the Paid
  Apps Agreement), and an app update carrying the one-line change. Apple reviews an in-app purchase
  with a build, so this cannot be a purely remote switch. Founding players (everyone who installed
  before the switch) keep it free, as SERVICES.md already says.
- Android later: Play Billing has its own product and its own proof; the `proof` field carries a
  `store` name so the relay knows which to check.

### In the apps

| Piece | Change |
|---|---|
| `shared/vectors/room-v1/`, `relay-v1/` (new) | JSON examples of every message: the room protocol as it is today, and the relay's. Tests in MatchKit and the app pin them. |
| `packages/MatchKit/Sources/MatchKit` | `RelayMessage` (the table above, pure Swift, tested on Linux from the examples); `RoomTiming` passed to `Room`. |
| `packages/MatchKit/Sources/MatchKitOnline` (new) | `OnlineTransport` over `URLSessionWebSocketTask`, behind a small socket protocol so tests use a fake; reconnect with the token; `OnlineRooms` (create, join, rejoin). |
| `Game/OnlineLobby.swift` (new, per app) | The nearby lobby's phases (`lobby / waiting / ready / refused / playing`) with a code in place of the list of games nearby. Much of `NearbyLobby` is shared: pull the common part out rather than copy it. |
| Screens | **Play online** on Home when `FeatureGate.isShown(Feature.online)`. *Start game* (rules, name) → the code, **Share**; *Enter code*; then the existing Ready to play, game header and reconnect views with online wording. |
| `RemoteGame.via` | `.online` already exists. |
| `Support/Features.swift` | `online` stays `.off` until the last stage. Debug builds show it with `-onlinePlay YES`, as nearby play did. |
| Links | Associated Domains `applinks:leluoware.com`; the app opens `/lelu-oware/join/<code>` straight into Ready to play. The website serves `apple-app-site-association` and a small page for people without the app (the code, and the App Store button). |
| Names | The nearby name, shown as *Online name*; same default and the same *· gold / · red* rule. |
| Analytics | `online.started`, `online.joined`, `online.finished` (result, rules), `online.dropped`. Only with consent, never names or codes. |
| Tests | `--online-demo`: the demo player Ama over `LoopbackTransport`, as `--nearby-demo`, so XCUITest, Maestro and App Review can see the screens on one phone. |

## 6. Who you are, without an account

| Option | Friction | Cost | Verdict |
|---|---|---|---|
| **A random install ID made on the phone, a seat token from the relay** | None | Nothing | **Use this.** |
| Sign in with Apple (and Google on Android) | A sign-in sheet before the first game | Free | Later, only if something must follow a person across phones (rankings, bans). |
| Amazon Cognito | A sign-in screen and an SDK in each app | Free to 10,000 monthly users, then US$0.015 each (Essentials) | Not needed. It would be the place to hold Apple and Google sign-in later. |
| Game Center identity | Must be signed in to Game Center | Free | Apple only. |

- The **install ID** is a random number kept in the Keychain. It is sent with `create` and `join`;
  the relay keeps only a hash of it, on the room, to count rooms per phone.
- The **seat token** is what `Room` already uses to take a seat back. Whoever holds it is that seat.
- The **room code** is six letters and digits from 31 that are hard to confuse (no `0 O 1 I L`):
  about 890 million codes. Wrong guesses are limited per phone and per network address, and a full
  room refuses everyone else.
- **The purchase** follows the Apple ID through StoreKit, with no account of ours. The first paid
  version checks on the creator's phone (`FeatureGate.canUse`). If people cheat it, the creator's
  phone sends its signed StoreKit transaction with `create` and the relay checks the signature.
- **If bots turn up:** App Attest (iOS) and Play Integrity (Android) let the relay refuse anything
  that is not the real app. Both are free. Not in the first version.

### Players who can be invited again (2026-11-18)

**Play again** needs to reach a phone that is not in a room, so three things were added. None is
an account: there is still no sign-in, email or name on the server.

- A **player ID**: a second random number made on the phone (Keychain), separate from the install
  ID. Unlike the install ID it is shown to the phones you play with, in the room's `player`
  message once seated (`shared/vectors/room-v2`), so that one of them can ask for you again. It
  names an installed app, not a person. A phone with no Keychain has none, and is never listed.
- A **player secret**: also random, also in the Keychain, shown only to the relay. The relay keeps
  a hash. The first phone to register an ID owns it, so knowing someone's ID does not let you act
  as them.
- The phone's **push token**, if the player allowed notifications. The relay keeps it with the
  player ID for 180 days after the phone last registered, and uses it only to deliver an
  invitation. **Settings ▸ Invitations** is off until the player turns it on (there, or with *Let
  them ask you too* under Recent players); turning it off tells the relay to forget the token.

As built: `PlayerIdentity`, `Invitations`, `RecentPlayers` and `OnlinePlay.playAgain` in the app;
`OnlineTransport.invite` and `RelayCall` in `MatchKitOnline`; `register`, `invite`, `block` and
`decline` in the relay (`shared/vectors/relay-v1`). A player is listed once a game with them has
started. An invitation arriving while the app is open is shown in the app (*Ama wants to play* ·
Join · Not now); Not now tells the phone that is waiting. The link opened is always made on the
phone from the code, never taken from the notification.

What this cannot do, and the app says so where it matters:

| Case | What happens |
|---|---|
| The app is deleted and installed again on the same phone | The Keychain usually survives, so the player ID does, and friends' lists still reach you. Your own Recent players list (kept with the app's data) is empty again. |
| A new phone, or a phone restored without its Keychain | A new player ID. Friends' old entries for you say *cannot be reached*; a link fixes it, and the next game puts the new ID in their list. |
| Notifications not allowed | You can still invite others. Nobody can invite you except by link. |
| Someone keeps asking | **Block** on their row. The relay then answers them `unreachable`, the same as for notifications off, so a block is not given away. Invitations are limited to 3 an hour to the same player and 20 an hour in all. |
| Is my friend online? | Not shown. The relay keeps no record of who has the app open, and a guess would be wrong often enough to mislead. |

## 7. Who checks the moves

| Option | Work | Risk | When |
|---|---|---|---|
| **Phones check each other; the server only relays** | None on the server. Built and tested for nearby play. | Oware: none worth having. There is no chance and nothing hidden; a phone that sends an illegal or altered game is refused by the other phone's replay and the state hash. A cheat can only stall or leave, which anyone can do. | **First version (Oware).** |
| **The server rolls the dice; phones check everything else** | One small handler: roll number *n* is made once with a secure random source, stored, and sent to every phone. A phone refuses a match whose *n*th roll is not the server's *n*th roll, or that skips one. | The creator's phone still applies the moves, but cannot choose or re-throw a die. | **Ludo with friends.** |
| **The server referees every move**, real engine: Swift on Lambda | The engines and `Room` rules are pure Swift and already tested on Linux in CI. `RoomRules.applying(intent, from:to:)` is a plain function: load the match, apply, save, send. Needs a Docker build for Amazon Linux and the Swift Lambda runtime (v2, 2025). | One set of rules everywhere. A new toolchain in the backend; cold start not measured yet. | **Recommended for stage 8**, after a one-day spike. |
| The server referees: rules rewritten in TypeScript | About 1,000 lines for both games' rules and house rules, plus Ludo's computer player, kept honest by shared test games. | A third copy of rules the owner is still tuning, after Swift and the Kotlin one planned for Android. It must pass the same `shared/vectors` as those two. | Fallback if the Swift spike disappoints. |

So: **trust the phones for Oware with friends, add server dice for Ludo, and put the real Swift
engine on the server before strangers, rankings or games that last days.**

Two things to do early whichever way stage 8 goes:
- **Shared test games as JSON** (a list of moves and the fingerprint after each). The Android plan
  (PR #112) already asks for these in a top-level `shared/vectors`, passed by the Swift engines and
  the Kotlin ones. Any server copy of the rules passes the same files; there is one set, not one
  per platform.
- **Move `OwareTable` and `OwareRoomRules` out of the app** into the engine package, so anything
  that is not the iOS app can use them.

How this meets the Android plan: Android is to be native Kotlin with the rules ported to Kotlin,
held to the Swift engine by `shared/vectors`. So the vectors will exist, and a TypeScript copy for
the server would be cheaper to trust than it would be alone. It would still be a third copy to
change with every rule. Swift on Lambda runs the engine the vectors are made from, and keeps the
count at two. That is why Swift is the recommendation and TypeScript the fallback. Nothing before
stage 8 depends on the choice: the relay never runs a rule, and an Android phone joins the same
rooms by speaking the pinned room and relay messages.

## 8. Cost

Prices for **US East (N. Virginia), checked 15 November 2026** on AWS's pricing pages. Free-tier
allowances are **not** counted, so real bills in the first year will be lower.

### What one game uses

| | Oware, 2 phones, 15 min | Ludo, 4 phones, 30 min |
|---|---|---|
| Connection minutes (with the lobby) | 34 | 132 |
| Messages in and out (moves, snapshots, pings every 10 s) | 700 | 5,600 |
| Lambda runs (128 MB, Arm, about 30 ms) | 360 | 2,300 |
| DynamoDB reads / writes | 350 / 100 | 2,300 / 700 |
| **Cost** | **about US$0.001** | **about US$0.009** |

These are estimates from counting messages on paper. Stage 2 measures a real scripted game and
this table is corrected then.

### Per month (API Gateway WebSocket + Lambda + DynamoDB on-demand)

| Games a month | Oware | Ludo, 4 phones |
|---|---|---|
| 0 | US$0.00 | US$0.00 |
| 100 | US$0.10 | US$0.90 |
| 1,000 | US$1 | US$9 |
| 10,000 | US$10 | US$90 |

Where 1,000 Oware games go: messages US$0.70, Lambda US$0.09, DynamoDB US$0.10, logs US$0.08, data
out US$0.03, connection minutes US$0.01. Messages are the bill, and pings are more than half of the
messages. If Ludo gets busy, the two savings are sending only new actions rather than the whole
match, and slower pings.

### The fixed floor

| Item | A month |
|---|---|
| WebSocket API, Lambda, DynamoDB table, custom domain, certificate (ACM), SSM parameters, AWS Budgets alerts | US$0 when idle |
| CloudWatch alarms | US$0 (ten are free; US$0.10 each after) |
| Logs | US$0.50 per GB written; nothing when idle. Retention one week (dev) and one month (prod) |
| Route 53 zone for `leluoware.com` | US$0.50, **already paid** for the website |
| A `dev` stage and PR previews | US$0 when idle |

**New fixed cost: US$0 a month.** Left out on purpose because each has a monthly fee: AWS WAF
(US$5 + US$1 a rule), Secrets Manager (US$0.40 a secret), customer KMS keys (US$1 each), NAT
gateways, load balancers, provisioned DynamoDB.

### The alternatives

| | Idle | 1,000 Oware games | For | Against |
|---|---|---|---|---|
| **(a) API Gateway WebSocket + Lambda + DynamoDB** | US$0 | about US$1 | Tells the server when a phone connects and drops; the AWS repo's template is already Lambda + DynamoDB; turn-based play suits it | 2-hour connections, 10-minute idle limit, every ping billed |
| (b) AppSync Events | US$0 | about US$1 (US$1.00 per million operations, US$0.08 per million minutes) | Publish and subscribe with almost no code | Connects, subscribes and pings are billed too; messages are counted in 5 KB steps; no drop notice that I could confirm; a referee later is more awkward |
| (b) AppSync GraphQL subscriptions | US$0 | about US$2–3 (US$4.00 per million mutations, US$2.00 per million updates) | The AWS repo already has an AppSync app | Dearer, and a schema for what is a pipe |
| (c) IoT Core (MQTT) | US$0 | about US$0.70 (US$1.00 per million messages, US$0.08 per million minutes; keep-alive pings free) | Cheapest connections; "last will" gives drop notices; the owner has used it | An MQTT library in each app and a custom authorizer; built for devices, not for players |
| (d) One small always-on server (Lightsail, US$5; Fargate 0.25 vCPU, about US$11 with its address, more with a load balancer) | US$5–30 | the same | Simplest code: rooms in memory, real timers, cheapest above about 5,000 Oware games a month | Paid when nobody plays; one machine to patch, watch and restart |
| (e) Game Center (`GKTurnBasedMatch` / `GKMatch`) | US$0 | US$0 | Free, with invites and matchmaking built in | Apple only, so no Android; needs Game Center sign-in |

**Pick (a).** If traffic ever passes several thousand games a month, the relay's core (kept free of
AWS calls so it can run locally, §10) moves to one small server without changing the apps.

## 9. Where the backend lives

### What the AWS repo is

Read on 2026-11-15, not changed. A private monorepo of self-contained serverless apps:

- **AWS CDK v2 in TypeScript**; npm workspaces over `apps/*`; Node 20, ES modules, strict TypeScript.
- Each app owns everything: `bin/app.ts` (only its stacks), `lib/` (stacks), `src/` (Lambda code,
  bundled with esbuild), `scripts/deploy.sh` and `destroy.sh`, `cdk.json` (`npx tsx bin/app.ts`),
  its own `package.json`, `tsconfig.json` and tests. **Apps share no code**, so any app can be
  lifted into its own repository (`npm run extract-app`).
- Stage from `STAGE` (`dev`, `test`, `prod`, and `pr-<n>` previews); stacks named
  `${stage}-<app>-<part>`; tags `App`, `Environment`, `ManagedBy: CDK`; region `us-east-1`.
- A generator, `npm run new-app -- --name <name>`, makes an API Gateway + Lambda + DynamoDB app
  with tests and three workflows: `<app>-deploy.yml` (run by hand), `<app>-destroy.yml` (type
  `DESTROY`), `<app>-pr-preview.yml` (a `pr-<n>` environment per pull request, removed on close and
  swept nightly). `ci.yml` lints, builds and tests every pull request.
- Tests first is the rule there too: jest with `aws-sdk-client-mock`, and integration scripts run
  against a deployed stage.
- Two apps today: `ghana-payments` (REST API, Lambda, DynamoDB, IoT Core, a monitoring stack with
  alarms to email) and `balance-booking` (Cognito, AppSync). Neither uses a WebSocket API or AWS
  Budgets yet, so those two parts are new there.

### In the AWS repo, or here?

| | AWS repo (`apps/lelu-play`) | This repo (`infra/play`, beside `infra/site`) |
|---|---|---|
| Tools and habits | Generator, deploy and destroy scripts, previews, CDK review agents: all there | Only the small website stack; previews and scripts would be rebuilt |
| Visibility | Private. The limits and the off switch stay out of public view | This repository is public today |
| Deploying | On its own, by hand, any day. An app release never waits for it | Same, but the workflows sit among the iOS ones |
| One change across both sides | Two pull requests, one in each repo | One pull request |
| Keeping the two sides in step | The wire format lives here as JSON examples; the backend keeps a copy and tests against it | Free |
| Swift engine on the server later (stage 8) | Built here, where the rules are, and published as a versioned file the backend's deploy fetches | By path |
| Cost | The same | The same |

**Pick: the AWS repo**, at `apps/lelu-play`. The price is keeping the wire format in step across
two repositories. That is handled by treating it as a contract: versioned JSON examples in
`shared/vectors/` (the folder the Android plan sets up for the engines' test games), tested by Swift
here and copied into the backend's tests by a script that records the commit it took them from.

### One backend, or one per game?

| | One app for both games | One app per game |
|---|---|---|
| Cost | The same: nothing is charged per app | The same |
| Code | One relay. It never looks inside `data`; a game is a name, a seat count and whether it has dice | The same relay twice, drifting apart |
| Running it | One set of alarms, one budget, one off switch (with a switch per game inside it) | Two of everything |
| A bad deploy | Reaches both games | Reaches one |
| Deploying on its own | A Ludo-only change redeploys the shared relay | Fully separate |

**Pick: one app.** The relay is as generic as MatchKit. A bad deploy is contained by the `dev`
stage, the scripted game that runs before `prod`, and versions on the wire. Splitting later is
cheap: rooms live for hours, so there is no data to move, and the game is in the first message.

### Layout of `apps/lelu-play`

```
apps/lelu-play/
  bin/app.ts                    STAGE → ${stage}-lelu-play-data, -relay, -watch
  lib/data-stack.ts             one DynamoDB table (on-demand in every stage, TTL on `expiresAt`)
  lib/relay-stack.ts            WebSocket API, the Lambdas, throttles, custom domain (prod)
  lib/watch-stack.ts            alarms, AWS Budget, the email topic, the off switch
  src/core/                     rooms, seats, relay, dice, limits: plain TypeScript, no AWS calls
  src/core/*.test.ts            jest, written first; includes a four-client room
  src/handlers/                 $connect, $disconnect, $default: thin, DynamoDB + post-to-connection
  src/games/                    oware.ts, ludo.ts: seat counts, dice or not, message size
  src/local/server.ts           the same core behind a plain WebSocket server, for a Mac
  test/contract/                JSON examples copied from this repo's shared/vectors (with the commit)
  test/integration/             a scripted game against a deployed stage: 2 clients, then 4
  scripts/deploy.sh, destroy.sh as the template's
  cdk.json, package.json, tsconfig.json, jest.config.cjs, README.md
.github/workflows/lelu-play-deploy.yml, -destroy.yml, -pr-preview.yml     (repo root, path-scoped)
```

Three places this departs from that repo's habits, each on purpose:
- **On-demand DynamoDB in `prod` too.** The convention is provisioned capacity for `test` and
  `prod`; that would be a monthly charge for an idle table.
- **Nothing is retained.** Rooms expire in hours, so `prod` has no backups and no deletion
  protection to pay for or clean up.
- **Tests must fail the build.** `ci.yml` there lets the test step fail without failing the run;
  this app's own workflows run its tests and stop on red.

Stages: `dev` (the owner's phones and CI), `prod`, and `pr-<n>`. `test` is not needed.
Deploying is that repo's way: Actions ▸ *Lelu Play — Manual Deploy* ▸ pick the stage; it runs
`cd apps/lelu-play && ./scripts/deploy.sh <stage>`, then the scripted game, and writes the address
in the run summary.

### Data, and how long it is kept

One table. Every item has `expiresAt`, and DynamoDB deletes it after that.

| Item | Holds | Removed |
|---|---|---|
| Room `ROOM#<code>` | game, versions, state (waiting / playing / closed), seats, last activity, hash of the creator's install ID | Waiting: 30 min. Playing: **24 h** after the last message, so a game survives the app closing (§5). Closed: 10 min |
| Seat `ROOM#<code>` / `SEAT#<n>` | hash of the seat token, connection id, last heard | With the room |
| Connection `CONN#<id>` | room and seat | On disconnect; at most 2 h 10 min |
| Dice (Ludo) `ROOM#<code>` / `ROLL#<n>` | the roll | With the room |
| Limit `LIMIT#<hash>#<window>` | a count, against a salted hash of the network address or install ID | 1 h |

**Not stored at all in the first version: the moves and the players' names.** They pass through
inside `data`, which the relay does not read or log. From stage 8 the referee stores the current
match (moves and seat names) on the room, with the same expiry.

## 10. Keeping it safe, cheap and working

### Abuse and the bill

A bot cannot be stopped from connecting. It can be stopped from costing money.

| Guard | What it does |
|---|---|
| Stage throttle on the WebSocket API | About 50 messages a second for everyone together, around 70 Oware games at once. Raise it when real traffic asks |
| Lambda reserved concurrency | A hard cap on how much can run at once, so the bill cannot run away |
| Limits per network address and per install | New connections, rooms made, wrong codes. Generous, because phone networks in Ghana put many people behind one address |
| Size limits | 4 KB a message for Oware, 32 KB for Ludo; a room is full at its seat count; an idle room closes |
| **Off switch** | One SSM parameter: `on`, `paused`, or off per game. When paused the relay answers `refused(paused)` and the app says "Online play is resting. Try again later." |
| AWS Budget | Emails at US$5, US$10 and US$20 for the month, on the `App: lelu-play` tag |
| Alarm on messages per hour | Faster than the budget (which lags by hours): too many messages → email, and the off switch flips itself |
| No AWS WAF | US$5 a month and more, and AWS's list of what it protects names REST APIs, not WebSocket APIs. Revisit only if the guards above are not enough |

Worst case with these in place: a bot running at the throttle all day costs under US$10 a day, and
the hourly alarm pauses the service long before that.

### Privacy

- **What leaves the phone:** the room code, the install ID, the name you chose (to the other
  players), your moves (to the other players), and the network address every internet connection
  shows.
- **What the server keeps:** rooms and seats for at most a few hours; hashes, not the install ID
  or address; no names and no moves in the first version; logs without names, codes or addresses
  for a week (dev) or a month (prod). No account, email, contacts or location, no advertising, no
  tracking.
- **Where:** AWS in the United States (`us-east-1`). The privacy policy says so (§12).
- **Privacy policy:** a "Play online" section in each app's `privacy.md`, like the nearby one, and
  a line in "The short version". It names AWS as the processor and gives the retention times above.
- **App Privacy label:** nearby play added nothing because nothing left the room. Online does send
  data to a server. Apple counts data as collected when it is kept "longer than what is necessary
  to service the transmitted request in real time", so a relay that stores no moves and no names
  may need no new entry. The safe answer is to add *Identifiers ▸ User ID* and *User Content ▸
  Gameplay Content*, not linked to the user, for App Functionality. Settle it against Apple's
  wording when stage 6 is written; from stage 8 (match stored) Gameplay Content is certain.
- **Deleting:** everything deletes itself within hours. The policy says so, with the contact email.
- **Children:** an invite room has no strangers and no chat. The name is the only free text and is
  seen only by someone holding the code. Check the age rating questions when submitting.

### Things a game needs

| Concern | First version | Later |
|---|---|---|
| A player stops without leaving | The other phone's reconnect sheet after the waiting time: *Keep waiting / Play the computer / Leave*, as nearby | A turn timer on the server with the referee |
| Abandoned rooms | Expire by TTL | |
| "Your turn" notifications | **None.** Both players are in the app; the game is live | Stage 9. APNs called straight from Lambda (free) or through SNS; needs the Push capability, an APNs key held as an SSM secure parameter, and a permission prompt. FCM for Android |
| Ludo's computer seats | The creator's phone chooses the move; the server rolls the die | The referee |
| Rematch | In the same room, both must ask (built) | |
| Game Center, achievements | None. The owner no longer wants Game Center at all, for leaderboards or achievements (2026-11-15); `FeatureFlags.gameCenter` stays `false` | |
| App Review | Review notes say online play needs two devices and give the demo (`--online-demo`) and a two-phone video, as for nearby | |

### Watching it, cheaply

- Lambda logs as one JSON line per event (room made, joined, dropped, closed, refused and why),
  never names, codes or message bodies.
- Free numbers from API Gateway, Lambda and DynamoDB (connections, messages, errors, throttles)
  cover the alarms: errors, throttles, messages per hour. No dashboard to start with.
- The deploy workflow's scripted game is the health check. Run it by hand any time.

### Testing

| Layer | What | Where it runs |
|---|---|---|
| Wire format | Every example in `shared/vectors/relay-v1/` and `shared/vectors/room-v1/` encodes and decodes the same on every side | Linux CI here; jest in the AWS repo |
| Relay core | Rooms, codes, seats, rejoin with a token, a full room, expiry, limits, pause, dice in order; a four-client room | jest, no AWS |
| Handlers | DynamoDB and post-to-connection calls, a gone connection | jest with `aws-sdk-client-mock` |
| Local run | `npm run dev` serves the same core on `ws://localhost`; two simulators play against it | A Mac |
| Deployed | A scripted two-client game, then four clients, against `pr-<n>` and `dev`; also measures messages per game for §8 | The AWS repo's preview and deploy workflows |
| `OnlineTransport` | Connect, drop, rejoin, the 2-hour reconnect, back from the background, against a fake socket | macOS CI here |
| App | Two `GameSession`s joined through a fake relay: the same checks as `RemoteGameTests` | Simulator CI |
| UI | `--online-demo` through XCUITest and Maestro: start, code shown, Ama joins, Ready, a game, a drop, a rematch | Simulator CI |
| Real phones | A checklist: Wi-Fi to mobile data mid-game, flight mode for 30 s, background for a minute, UK to Ghana, an old and a new app version together | By hand, before each TestFlight |

## 11. Order of work

Each stage is one pull request (or one in each repo), tests first, behind `online: .off` until
stage 6. Effort is rough, for one person.

| Stage | Repo | Pull request | Effort | The owner does by hand |
|---|---|---|---|---|
| 0 | — | Decisions: §12 | done 2026-11-15 | Create the AWS Budget email |
| 1 | here | `test(matchkit): pin the room messages` then `feat(matchkit): the relay wire format and room timings` — JSON examples of every room message in `shared/vectors/room-v1/` (a version 2 if the automatic form needs tidying); `relay-v1/`, `RelayMessage`, `RoomTiming` (nearby keeps 2 / 4 / 15 s) | 2–3 days | — |
| 2 | AWS | `feat(lelu-play): rooms and a relay` — `npm run new-app`, WebSocket API in place of REST, the core with its tests, local server, scripted game, preview workflow; deploy `dev` | 3–4 days | Run the first `dev` deploy |
| 3 | AWS | `feat(lelu-play): limits, alarms and an off switch` — throttles, caps, limits, budget, alarms, pause, the `requireProof` setting (off), `play.leluoware.com` in the website's account | 2 days | Confirm the alarm email |
| 4 | here | `feat(matchkit): an online transport` — `MatchKitOnline`, reconnect and rejoin, the saved game a phone rejoins from after a relaunch, tests on a fake socket | 4 days | — |
| 5 | here | `feat(oware): play online with a friend (hidden)` — lobby, code and Share, Enter code, Ready, reconnect wording, the Rejoin card on Home after the app was closed, *Start game* tested both free and paid, links, `--online-demo`, analytics; website: `apple-app-site-association` and the join page | 6–8 days | Turn on Associated Domains for the App ID. Try it on two phones, one on mobile data (`-onlinePlay YES`) |
| 6 | both | `feat(oware): turn on online play` — deploy `prod`; privacy page, label, review notes and video, What's New; `online` to `.free` | done 2026-11-18, then review | Privacy label and review notes in App Store Connect |
| 7 | both | Ludo with friends — after Ludo nearby steps 1–3. `feat(lelu-play): dice for Ludo`; `feat(ludo): play online with friends` (2–4 seats, computer seats, server dice for every seat checked in `LudoMatch`) | 1–2 days + 5–7 days | Four devices for a real game |
| 8 | both | The server referees — a spike first (Swift on Lambda: build, size, cold start); the server passes `shared/vectors`; `OwareTable` and `OwareRoomRules` into a package; no phone in charge | 1–2 weeks | Decide Swift or TypeScript after the spike |
| 9 | both | Games that last days, "your turn" notifications | 1–2 weeks | Push capability, an APNs key |
| 10 | both | Play with anyone — queue, the computer when nobody waits, names, report and block, App Attest; rankings after | 2–3 weeks, then ongoing | Age rating answers; someone to read reports |

Stages 1–6 are **about four weeks** of work for Oware with a friend. Stages 1–3 can go
ahead while nearby play's redesign steps 3–4 finish: the Connection lost sheet and Rejoin card they
add are the same views online needs.

### Colours on the two phones (decided 2026-11-18)

Each side keeps one colour on both phones: the player who made the game is gold, the one who
joined is red, and each phone puts its own player at the bottom. Showing every player as gold on
their own phone was considered and not done: houses change hands in Nam-Nam and are drawn in the
owner's colour, so the same house would be gold on one phone and red on the other, two friends
talking about "the red houses" (or sharing a screenshot) would mean opposite things, and two
players with the same name are told apart by colour ("Oware Player · red"). The plates beside
the board say *You* on this phone's side.

## 12. Decisions and open questions

Decided by the owner on 2026-11-15:

| Question | Decision |
|---|---|
| Free or paid | **Free at first, easy to switch to paid.** The paid path is built and tested now and left off (§5, *Free now, paid later*). |
| Home of the backend | The AWS repo, as `apps/lelu-play`, one app for both games. |
| AWS account | The website's. `play.leluoware.com` sits in the existing hosted zone. |
| Region | `us-east-1` for now. Moving later means a new deploy and an app update with the new address; no data needs moving, since nothing is kept beyond a day. |
| A game survives the app being closed | **Yes**, in the first version, because phone networks cut out (§5, *A game that survives the app closing*). Done with saved games and 24-hour rooms, not by bringing the referee forward. |
| Ludo: who rolls for a computer seat | The server, like every other roll. |
| Game Center | Not wanted, for online play, leaderboards or achievements. |

Decided while building (2026-11-15):

| Question | Decision |
|---|---|
| Tidy the room messages before online play depends on them? | **Yes: room protocol version 2**, plain JSON, in `shared/vectors/room-v2`. A phone refuses every version but its own, so a phone on the first nearby play and one on this cannot play nearby together; each is told which to update. |
| The invitation link | `https://leluoware.com/lelu-oware/join?c=<code>`: the code as a query, so the join page is one static page. The app also opens `/join/<code>` and its own `leluoware://join?c=<code>`. Where this plan writes `/join/K7M2QD`, read the query form. |
| How a friend is invited | **Invite a friend** makes the game and opens the share sheet in one tap. The waiting screen shows the code. The code box takes a pasted link or message. (A QR code of the link was shown at first; removed 2026-11-18, below.) |
| The joining phone's own move | Sown the moment it is tapped; the host's snapshot confirms it, and a move the host never got is taken back after 8 s. |

Decided by the owner on 2026-11-18 (the brief "Multiplayer invitation and replay improvements"):

| Question | Decision |
|---|---|
| Link, code or QR | **The link is the way in.** No QR code ("the link will do"). The code stays as the fallback: **Join with code** is a secondary button that opens the code box. |
| How long an unanswered invitation lasts | A waiting room is kept **2 hours** (was 30 minutes), so a link read late still works while the creator is waiting. |
| A game that is over | The relay answers `ended` for a room that was there and is closed or expired, and `notFound` only for a code nobody has. The app says which. |
| Rematch | Stays in the same room, both must agree. Added: **Not now**, and a request nobody answers lapses after 60 seconds. |
| Recent players, and **Play again** | The last five people played online are kept **on the phone**. Play again makes a room and the relay sends that player a **notification** (Apple's push service; free). This is the one place the relay keeps something for longer than a day: §6, *Players who can be invited again*. No online or offline indicator: the relay does not know who is in the app. |
| Limits, alarms and the off switch (stage 3) | Built with the above, before online play is switched on for anyone. |
| Quick Match | **Investigated, not built.** §14. |
| Four players | Oware is a game for two. The relay seats two to four and Ludo will use that; nothing in the Oware app is for four. |

Still open. Each has a proposal, and the work goes ahead on the proposal unless the owner says
otherwise:

1. **How long before the "Reconnecting…" sheet?** Proposed: "Reconnecting…" after 25 s, the sheet
   after 90 s (nearby: 4 s and 15 s).
2. **May the creator still turn someone away** who has the code (the **Not now** button), or does
   having the code let you straight in? Proposed: keep **Not now**.
3. **One name or two?** Proposed: the nearby name is also the online name.
4. **Stage 8: Swift on the server, or rules in TypeScript?** Proposed: Swift, after a spike. Either
   way it passes the same `shared/vectors` as the Swift and Kotlin engines. Not needed before
   stage 8.
5. **If the creator never comes back,** the guest can only finish against the computer until
   stage 8. Is that acceptable for the first version, or should the referee come before Ludo?
6. **Does a friend who arrives by the link still press Ready, and can the creator still say Not
   now?** Built: yes to both. Proposed: for a link the creator sent, the game starts when the
   creator taps Start.

## 13. Not verified

- **Game sizes.** Messages per game are counted on paper. Stage 2 measures them.
- **The 10-minute idle limit and ping frames.** AWS says control frames are not billed. Whether
  they keep an idle connection open is not stated; reports say no. The plan does not rely on it:
  the room's own pings keep the connection busy.
- **AWS WAF and WebSocket APIs.** AWS's list of protected resources names "API Gateway REST API"
  only. I found no page that says WebSocket APIs are refused; the plan assumes they are.
- **AppSync Events drop notices.** I could not confirm it tells a server when a client drops.
- **Swift on Lambda.** The runtime's version 2 exists and targets Amazon Linux 2023. Cold start and
  package size for these engines are not measured; that is stage 8's spike.
- **From memory, not re-checked today:** Lambda on Arm at US$0.0000133 per GB-second; data out at
  US$0.09 per GB; a public IPv4 address at US$0.005 an hour (the Fargate row); SNS mobile push at
  US$0.50 per million; DynamoDB TTL deletes being free; IoT Core messages at US$1.00 per million in
  `us-east-1` (the page shows that rate in an Ireland example).
- **The Android plan.** Known here only from a summary of PR #112 (Kotlin, `shared/vectors`); its
  text was not read. If its folder names differ, follow that plan's.
- **Which AWS account the AWS repo deploys to.** Not looked up, so that no account number is
  copied here.

## 14. Quick Match: investigated 2026-11-18, not built

The owner asked whether **Play online ▸ Quick Match** (find anyone, no link, no code) is worth
building now. **No: wait.** This section is the finding, kept here so it need not be done twice.
It is stage 10 in §11 and still depends on stages 8 and 9.

### Can the relay do it?

Yes, with what is there. Nothing new to run, no new service, no always-on connection beyond the
one a waiting phone already holds.

| Piece | How |
|---|---|
| The queue | One item per waiting phone in the same DynamoDB table (`QUEUE#<game>#<seats>#<rules>`), with the connection and a few minutes' expiry. A new request `match {game, seats, rules}`: if someone compatible is waiting, the relay makes a room and seats both (the existing `room` answer); if not, it adds this phone to the queue. `$disconnect` and `leave` take it out. |
| Two and four seats | The queue key carries the seat count. A Ludo table of four fills as phones arrive and starts with computer seats after a wait. Oware is always two. |
| Who is in charge | Today the creator's phone. Between strangers that is not acceptable (a stranger's phone could stall or cheat), so the server referee (stage 8) comes first. |
| Names | Seen by strangers, so they become content the app is answerable for (App Review 1.2): fixed or filtered names, report, block, a published contact, and someone to read reports. |

### Game Center instead?

`GKMatchmaker` would do the pairing for nothing, and Apple carries the queue. Against it: Apple
only (an Android app is planned, §2); every player must be signed in to Game Center, which the
owner has ruled out (§12, 2026-11-15); and its matches would still need our room on top, or a
second way of playing a game. It would save a few days of queue code and cost the Android half of
the audience. **Not worth it.**

### What it would cost to run

AWS prices as checked for §8 on 15 November 2026 (not checked again for this section); free-tier
allowances not counted. Assumptions, all guesses until there are real players: each daily player
searches twice a day; a search waits two minutes on average, pinging every 10 seconds; half the
searches end in a game.

| Daily players | Searches a month | **Added by Quick Match** (waiting and the queue) | Games it starts (already costed in §8 at about US$0.001 each) | Together |
|---|---|---|---|---|
| 10 | 600 | under US$0.05 | 150: US$0.15 | about US$0.20 |
| 100 | 6,000 | about US$0.20 | 1,500: US$1.50 | about US$2 |
| 1,000 | 60,000 | about US$2 | 15,000: US$15 | about US$17 |
| 10,000 | 600,000 | about US$20 | 150,000: US$150 | about US$170 |

A search costs about US$0.00003: 24 pings and answers (US$1.00 a million messages), 12 short Lambda
runs, a handful of DynamoDB writes, and two connection minutes (US$0.25 a million). Notifications
("someone is looking for a game") go through Apple and cost nothing. There is no third-party
service, no extra database and no fixed monthly charge: an empty queue costs US$0. The existing
relay is the same cost with or without it.

The cost that matters is not on the AWS bill: the server referee (1–2 weeks, §11 stage 8), names
and report-and-block (part of stage 10's 2–3 weeks), and reading reports for as long as it is on.

### When only one person is looking

With few players this is nearly every search, so it decides whether the feature reads as working.

| Option | Verdict |
|---|---|
| A waiting screen with a count-up | Needed, but alone it is the "empty room" §3 warns of. Cap it at about 30 seconds. |
| **Offer the computer after the wait** | **Yes.** "Nobody is looking right now. Play Kofi while you wait?" The Journey's opponents are already there. |
| **Invite a friend from the waiting screen** | **Yes.** It is the same room; one button. |
| Keep looking while using the rest of the app | Only while the app is open: iOS ends the connection in the background. Worth doing once the queue exists; small. |
| Tell me when someone is looking | Later. It needs notification permission and, to be any use, enough players that it fires. At 10 daily players it would be silence or spam. |

### Recommendation

**Wait.** Online play is not switched on for anyone yet, so there are no players to match. Build
order stays as §11: friends by link, rematch and play again (done or in hand), then the referee,
then Quick Match. Look again when online games with friends pass about **100 a day**, the point
at which two strangers looking in the same minute stops being luck; the relay's logs
(`room.created` per day) give that number for free.
