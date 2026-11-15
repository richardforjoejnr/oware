# Playing online: plan

How two to four phones in different places play one game, for every app in this repository, with
a small backend on AWS. This is a **plan for the owner to review (2026-11-15). Nothing is built
and nothing is deployed.** It builds on [MULTIPLAYER.md](MULTIPLAYER.md) (the layers, MatchKit,
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
| Online is behind `FeatureGate`; one-time unlock; the host pays; invited friends play free | SERVICES.md §1, `Feature.table` | **Kept**, with one proposal: start as `.free` while it is new, then switch to `.unlock(hostPays: true, …)` (open question 1). Tips cannot be sold yet either (Paid Apps Agreement), so paid online could not ship today anyway. |
| No accounts; Game Center is the only sign-in and optional | SERVICES.md §1 | **Kept.** No sign-in for friends-only play (§6). |
| No adverts; worldwide audience | SERVICES.md §1 | **Kept.** |
| Online goes through **Game Center** (`GameCenterTransport`, `GKTurnBasedMatch`) | MULTIPLAYER.md, NEARBY_PLAY.md, SERVICES.md §8 | **Changed: AWS instead. This plan replaces SERVICES.md §8's "still to build" list.** Game Center is free but Apple-only, and an Android version is planned (PR #112). It also needs every player signed in to Game Center, which is off in the app today (`FeatureFlags.gameCenter = false`). |
| Messages at most 64 KB (Game Center's limit) | MULTIPLAYER.md §2 | **Tightened to 32 KB** for online: API Gateway bills in 32 KB steps and closes a connection on a larger frame. An Oware match is under 1 KB; a long Ludo match needs watching (§4). |
| A game does not survive both apps being closed; no undo, no hints | NEARBY_PLAY_REDESIGN.md decision 7 | **Kept for the first version.** Games that last days ("your turn" notifications) are a later stage (§11, stage 9). |
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
| Empty seats played by the computer | Run on the creator's phone, as in the nearby plan. They move to the server with the referee (stage 8). |
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
| `create {game, protocol, seats, install}` | `room {code, peer, token, peers}` |
| `join {code, install}` | `peer {peer, state: joined / left / dropped}` |
| `rejoin {code, token}` | `data {from, data}` |
| `data {to?, data}` | `rolled {n, value}` (Ludo) |
| `roll` (Ludo) | `refused {reason: notFound / full / paused / needsUpdate / tooMany}` |
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
  numbers: proposed ping every 10 s, "Reconnecting…" after 25 s, give up after 90 s (open question 4).
  `Room`'s three timings become a value passed in, so each transport sets its own.
- **Knowing your own link is down.** WebSocket ping frames are free on API Gateway and are answered
  by the gateway, so the phone can check its own link every few seconds without cost.
- **Different versions.** `create` carries the game, the room protocol version and the match format
  version. A phone that joins with other numbers gets `refused(needsUpdate)` and the existing
  "Update Lelu Oware on both phones" message. The relay's own format has a version too; the relay
  serves the last two.

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
| Room `ROOM#<code>` | game, versions, state (waiting / playing / closed), seats, last activity, hash of the creator's install ID | Waiting: 30 min. Playing: 2 h after the last message. Closed: 10 min |
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
- **Where:** AWS in the United States (`us-east-1`). The privacy policy says so (open question 5).
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
| Ludo's computer seats | The creator's phone | The referee |
| Rematch | In the same room, both must ask (built) | |
| Game Center, achievements | None for online games with friends, as for nearby (easy to farm) | |
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
| 0 | — | Decisions: the open questions in §12 | — | Answer them. Confirm which AWS account. Create the AWS Budget email |
| 1 | here | `test(matchkit): pin the room messages` then `feat(matchkit): the relay wire format and room timings` — JSON examples of every room message in `shared/vectors/room-v1/` (a version 2 if the automatic form needs tidying); `relay-v1/`, `RelayMessage`, `RoomTiming` (nearby keeps 2 / 4 / 15 s) | 2–3 days | — |
| 2 | AWS | `feat(lelu-play): rooms and a relay` — `npm run new-app`, WebSocket API in place of REST, the core with its tests, local server, scripted game, preview workflow; deploy `dev` | 3–4 days | Run the first `dev` deploy |
| 3 | AWS | `feat(lelu-play): limits, alarms and an off switch` — throttles, caps, limits, budget, alarms, pause, `play.leluoware.com` | 2 days | Confirm the alarm email. If the account differs from the website's, delegate `play.leluoware.com` to it |
| 4 | here | `feat(matchkit): an online transport` — `MatchKitOnline`, reconnect and rejoin, tests on a fake socket | 3 days | — |
| 5 | here | `feat(oware): play online with a friend (hidden)` — lobby, code and Share, Enter code, Ready, reconnect wording, links, `--online-demo`, analytics; website: `apple-app-site-association` and the join page | 5–7 days | Turn on Associated Domains for the App ID. Try it on two phones, one on mobile data (`-onlinePlay YES`) |
| 6 | both | `feat(oware): turn on online play` — deploy `prod`; privacy page, label, review notes and video, What's New; `online` to `.free` or `.unlock` | 2 days, then review | Privacy label and review notes in App Store Connect. If paid: the product, with the build |
| 7 | both | Ludo with friends — after Ludo nearby steps 1–3. `feat(lelu-play): dice for Ludo`; `feat(ludo): play online with friends` (2–4 seats, computer seats, server dice checked in `LudoMatch`) | 1–2 days + 5–7 days | Four devices for a real game |
| 8 | both | The server referees — a spike first (Swift on Lambda: build, size, cold start); the server passes `shared/vectors`; `OwareTable` and `OwareRoomRules` into a package; no phone in charge | 1–2 weeks | Decide Swift or TypeScript after the spike |
| 9 | both | Games that last days, "your turn" notifications | 1–2 weeks | Push capability, an APNs key |
| 10 | both | Play with anyone — queue, the computer when nobody waits, names, report and block, App Attest; rankings after | 2–3 weeks, then ongoing | Age rating answers; someone to read reports |

Stages 1–6 are **about three to four weeks** of work for Oware with a friend. Stages 1–3 can go
ahead while nearby play's redesign steps 3–4 finish: the Connection lost sheet and Rejoin card they
add are the same views online needs.

## 12. Open questions for the owner

1. **Free at first, or paid from day one?** The earlier decision is a one-time unlock where the
   host pays. Proposed: `.free` while it is new (in-app purchases cannot ship until the Paid Apps
   Agreement is active, and a game costs a tenth of a cent), then `.unlock(hostPays: true)` with
   founding players included. Or hold online back until it can be sold.
2. **Is the AWS repo the right home**, as `apps/lelu-play`? And is that name right?
3. **Which AWS account?** The same one as the website keeps `play.leluoware.com` simple. A separate
   one keeps the bill and the blast apart, and costs one more hosted zone (US$0.50 a month).
4. **How long to wait for a lost phone online?** Proposed: "Reconnecting…" after 25 s, give up
   after 90 s (nearby: 4 s and 15 s).
5. **Region.** `us-east-1` matches everything else and is the cheapest. Ireland or London would be
   nearer UK and Ghana players and a simpler story under UK and EU privacy law, at almost the same
   price. Turn-based games do not feel the distance.
6. **May the creator still turn someone away** who has the code (the **Not now** button), or does
   having the code let you straight in?
7. **Should a game survive the app being closed** in the first version? Proposed: no, as nearby.
   Yes means stage 8 first.
8. **One name or two?** Proposed: the nearby name is also the online name.
9. **Ludo: who rolls for a computer seat?** Proposed: the server, like every other roll.
10. **Stage 8: Swift on the server, or rules in TypeScript?** Proposed: Swift, after a spike. Either
    way it passes the same `shared/vectors` as the Swift and Kotlin engines.
11. **Game Center.** Still wanted for leaderboards and achievements only? This plan no longer uses
    it for online play.

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
