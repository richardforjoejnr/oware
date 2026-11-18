# Room protocol, version 2

What the phones in one game send each other: nearby over Bonjour, online inside the relay's
`data`. Swift: `Envelope` and `RoomMessage` in `packages/MatchKit`.

Every message is an envelope:

```json
{"protocolVersion": 2, "sequence": 3, "body": {"type": "hello", "name": "Kofi"}}
```

- `protocolVersion`: read first, on its own. A phone that reads any number but its own does not
  read the body: it tells its player who should update. **This key keeps its name and place in
  every version**, because it is the one thing an old app must still find.
- `sequence`: counts up per sender. A message with a number not higher than the last one heard
  from that sender is dropped.
- `body`: one object with a `type`, and that kind's values beside it.

| `type` | Who sends it | Beside it |
|---|---|---|
| `hello` | A phone asking to join, or coming back | `name`; `rejoin` (the token from its `welcome`) when coming back |
| `welcome` | The phone in charge | `seat`, `token`, `names` (seat number as text → name), `snapshot` (the game's match) |
| `refused` | The phone in charge | `reason`: `roomFull`, `declined` or `needsUpdate` (with `hostVersion`) |
| `intent` | Any other phone | `intent`: what it asks for, in the game's own form |
| `snapshot` | The phone in charge | `snapshot`: the whole match, in the game's own form |
| `ping`, `bye` | Anyone | nothing |
| `player` | Any phone that has a player number, once seated | `player`: its player number (see [relay-v1](../relay-v1/README.md)) |

- A missing optional is left out, never `null` (`rejoin`, `stateHash`, `resignedBy`,
  `rematchDeclinedBy`, `rematchLapsedFor`).
- Tokens and match ids are UUIDs. Swift writes capitals and reads either case.
- Key order is free.
- A `play` intent says its turn in `ply` (added 2026-11-19): how many moves the game had when
  it was made. The phone in charge refuses a move for any other turn, so a copy that arrives
  late is not played as another move. Without `ply` (an older app) the turn is not checked.
- `player` was added to version 2 on 2026-11-18. A phone that does not know it drops the message
  and plays on (as TestFlight builds 1.0.10 to 1.0.12 do); neither phone then lists the other
  under Recent players.

## Lelu Oware (`oware/`)

The match is an `OwareTable` and an intent is a `TableIntent`
(`apps/lelu-oware/Oware/Sources/Game/RemoteGame.swift`); the match inside the table is an
`OwareMatch` (`packages/OwareEngine`), format version 2.

- Players are numbers: `0` South (the phone in charge, seat 0), `1` North.
- `ready` and `rematchAsked` are lists of players, lowest first.
- `paces` is an object, player number as text → seconds: `{"0": 0.35, "1": 0.6}`.
- `stateHash` is `GameState.fingerprint` of the position after `houses` (and `resignedBy`).
- `houses` are the houses played, 0–11, in order. There is no board in the message: each phone
  replays the moves through its own rules.
- An intent is one object with a `type`: `play` (`house`), `resign`, `rematch`, `declineRematch`,
  `pace` (`pace`, seconds), `ready` (`stateHash`).

### Rematch: asked, declined, lapsed

Added to version 2 on 2026-11-18, before any App Store build spoke it (TestFlight builds 1.0.10
to 1.0.12 did; see below).

- `rematch` puts the asker in `rematchAsked`. When both are in it the phone in charge starts the
  next game and empties the list.
- `declineRematch` is the other player's "Not now". The phone in charge empties `rematchAsked`,
  sets `rematchDeclinedBy` to whoever declined and adds one to `rematchRound`. It changes nothing
  unless the other player, and only the other player, has asked.
- A request nobody answers for 60 seconds lapses: the phone in charge empties `rematchAsked`, sets
  `rematchLapsedFor` to whoever asked and adds one to `rematchRound`. No message asks for this.
- The next `rematch` removes `rematchDeclinedBy` and `rematchLapsedFor`.
- `rematchRound` counts requests that ended without a game. For the same match, a snapshot with a
  higher `rematchRound` is newer, though fewer players are asking in it. It is left out while 0,
  and a table without it reads as 0.

A phone on a build from before this (it can only be a TestFlight one) still plays whole games
with a newer phone, and a rematch both players ask for still starts. It has no Not now button;
it drops a `declineRematch` it is sent (a message it cannot read is ignored); and it does not
take a snapshot in which a request has ended, so it goes on showing its own request as waiting.

## Version 1

The first nearby play (October 2026) spoke version 1: the same envelope, with the body in the
form Swift writes by itself (`{"hello": {"name": "Kofi"}}`, values under `_0`). A phone on
version 2 does not play with one on version 1; each tells its player which phone to update.
