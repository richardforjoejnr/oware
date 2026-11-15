# Room protocol, version 1

What the phones in one game send each other: nearby over Bonjour, online inside the relay's
`data`. This is the JSON that Swift's automatic `Codable` writes for `Envelope` and `RoomMessage`
(`packages/MatchKit`), pinned as it was on 2026-11-15, when Lelu Oware's nearby play already used
it.

Every message is an envelope:

```json
{"protocolVersion": 1, "sequence": 3, "body": {"<kind>": { … }}}
```

- `protocolVersion`: read first. A phone refuses a higher number than its own and asks the
  players to update.
- `sequence`: counts up per sender. A message with a number not higher than the last one heard
  from that sender is dropped.
- `body`: an object with exactly one key, the kind of message.

| Kind | Who sends it | Inside |
|---|---|---|
| `hello` | A phone asking to join, or coming back | `name`; `rejoin` (the token from its `welcome`) when coming back |
| `welcome` | The phone in charge | `seat`, `token`, `names` (seat number as text → name), `snapshot` (the game's match) |
| `refused` | The phone in charge | `_0`: one of `roomFull`, `declined`, `needsUpdate` (`hostVersion`) |
| `intent` | Any other phone | `_0`: what it asks for, in the game's own form |
| `snapshot` | The phone in charge | `_0`: the whole match, in the game's own form |
| `ping`, `bye` | Anyone | `{}` |

Things another language must copy exactly:

- A case with no values is an empty object: `{"ping": {}}`, `{"roomFull": {}}`.
- A value without a name is under `_0`: `{"intent": {"_0": …}}`, `{"pace": {"_0": 0.6}}`.
- A missing optional is left out, never `null` (`rejoin`, `stateHash`, `resignedBy`).
- Tokens and match ids are UUIDs in capitals.
- Key order is free.

## Lelu Oware (`oware/`)

The match is an `OwareTable` and an intent is a `TableIntent`
(`apps/lelu-oware/Oware/Sources/Game/RemoteGame.swift`); the match inside the table is an
`OwareMatch` (`packages/OwareEngine`), format version 2.

- Players are numbers: `0` South (the phone in charge, seat 0), `1` North.
- `ready` and `rematchAsked` are lists of players **in any order**.
- `paces` is a flat list, player then seconds, **pairs in any order**: `[0, 0.35, 1, 0.6]`.
- `stateHash` is `GameState.fingerprint` of the position after `houses` (and `resignedBy`).
- `houses` are the houses played, 0–11, in order. There is no board in the message: each phone
  replays the moves through its own rules.
