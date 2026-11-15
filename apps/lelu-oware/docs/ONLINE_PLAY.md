# Lelu Oware: playing online (plan)

Two people in different places, one game, over the internet. A friend joins with a 6-letter code or
a link. The whole plan, shared with Lelu Ludo, is [ONLINE_PLAY.md](../../../docs/ONLINE_PLAY.md):
the relay on AWS, cost, privacy and the order of work. This file is what is specific to Oware.
Planned 2026-11-15. What is built so far, and how to try it, is in [STATUS.md](STATUS.md) ▸ Online play.

**Oware goes first**, because nearby play already built everything above the transport.

## What is reused as it is

| Piece | From |
|---|---|
| `OwareMatch`, `OwareIntent`, `GameState.fingerprint` | `packages/OwareEngine` |
| `OwareTable`, `OwareRoomRules`: Ready handshake, state hash, rematch, shared sowing speed | `Game/RemoteGame.swift` |
| `MatchLink`, `GameSession` with a remote seat, the turned board | nearby steps 4–5 |
| Ready to play, "left the game", reconnect; the Connection lost sheet and Rejoin card when redesign step 3 lands | [NEARBY_PLAY_REDESIGN.md](NEARBY_PLAY_REDESIGN.md) |
| No undo, no hints, Resign, Rematch; no achievements for games with friends | nearby decisions |

The creator's phone stays in charge of the game (South, moves first), and each phone replays every
move through its own engine. Oware has no dice and nothing hidden, so a relay that only passes
messages is enough between friends.

## What is new

| Piece | Change |
|---|---|
| Home | **Play online**, shown when `FeatureGate.isShown(Feature.online)` |
| `Game/OnlineLobby.swift` | The nearby lobby's phases with a code in place of *Games nearby*: **Start game** (rules, name) → the code and **Share**; **Enter code**; then Ready to play. The shared part of `NearbyLobby` is pulled out, not copied |
| Links | `https://leluoware.com/lelu-oware/join?c=<code>` opens the app at Ready to play (Associated Domains); without the app, a page with the code and the App Store button |
| Wording | *Reconnecting to Ama…* waits longer than nearby (proposed 25 s, then 90 s); no "stay close" or Wi-Fi help; "Online play is resting" when the service is paused |
| `Support/Features.swift` | `online` stays `.off` until the last stage; `-onlinePlay YES` shows it in Debug builds |
| Tests | `--online-demo` (Ama over `LoopbackTransport`), `OnlineUITests`, `online-demo.yaml` for Maestro |
| Privacy page, App Privacy label, review notes | A "Play online" section; see the shared plan §10 |

## Before it is turned on

- [ ] Two iPhones on different networks (one on mobile data): start, share the link, join, a full
      game, rematch.
- [ ] Wi-Fi to mobile data in the middle of a game; flight mode for 30 s; the app in the background
      for a minute: the same game each time.
- [ ] One phone leaves for good: the other is offered the computer, and the room closes.
- [ ] A wrong code, a used code, a full room, an old app version with a new one: a clear message each.
- [ ] A game longer than two hours carries on (the connection is renewed without the player seeing).
- [ ] Close the app mid-game on one phone, open it a few minutes later: Home shows the Rejoin card and the game carries on. Then the same with both phones closed.
- [ ] VoiceOver: the code is read letter by letter; connection changes are announced.
- [ ] UK to Ghana, once.
