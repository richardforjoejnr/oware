# Relay messages, version 1

What a phone and the relay (`apps/lelu-play` in the AWS repo) send each other over the WebSocket.
Each message is one JSON object with a `type`. Swift: `RelayRequest` and `RelayEvent` in
`packages/MatchKit/Sources/MatchKit/RelayMessage.swift`.

| Phone → relay (`to-relay/`) | Relay → phone (`from-relay/`) |
|---|---|
| `create {v, game, protocol, format, seats, install, proof?}` | `room {code, peer, token, peers}` |
| `join {v, code, game, protocol, format, install}` | `peer {peer, state: joined / left / dropped}` |
| `rejoin {v, code, token}` | `data {from, data}` |
| `data {to?, data}` | `rolled {n, value}` (Ludo) |
| `roll` (Ludo) | `refused {reason}` |
| `leave` | `pong` |
| `ping` | |
| `register {v, game, player, secret, push?}` | `registered` |
| `invite {v, player, secret, to, name}` | `invited {to}` |
| `block {v, game, player, secret, who, on}` | `blocked {who, on}` |
| `decline {v, code, player}` | `declined {player}` (to the phone waiting in that room) |

- `v` is this format's version, sent with the first message on a connection.
- `game` is `oware` or `ludo`; `protocol` is the room protocol version (now 2: [room-v2](../room-v2/README.md));
  `format` is the game's match format version. A phone that joins a room made with other numbers
  gets `refused needsUpdate`.
- `install` is a random ID kept on the phone. The relay keeps only a hash of it.
- `proof` is the creator's signed purchase, for when starting a game is paid. Optional, and not
  checked while online play is free.
- `code` is six characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no `0 O 1 I L`).
- `peer` names a phone in the room: `p0` is the one that made the room and is in charge of the
  game; the others are `p1`, `p2`, `p3`. A phone that rejoins gets the same name back.
- `token` takes the seat back with `rejoin`. Whoever holds it is that seat, so it is kept secret
  (Keychain) and the relay keeps only a hash.
- `data` is one room message as JSON text, passed on untouched and never read or logged by the
  relay (the text in these examples is from room protocol version 1; the relay does not care). Without `to` it goes to everyone else in the room.
- `player` is a player number: 32 lowercase hex characters a phone makes for itself and gives the
  phones it plays (in the room's `player` message), so one of them can ask it for another game.
  `secret` goes only to the relay, which keeps a hash: it proves a later `invite` or `block`
  comes from the phone that registered that number. Both are kept in the Keychain.
- `push` is `{token, env}`: the phone's notification token from Apple as hex, and `sandbox` (a
  build run from Xcode) or `production`. Without it the phone is known but cannot be notified.
- `invite` is taken only from the connection that made a room, and invites into that room: the
  relay sends `to` a notification with the room's code, `from` (the asker's player number),
  `name` and the join link. `to` and `who` are player numbers.
- `decline` is "Not now" to an invitation. The relay says nothing back to the sender.
- `refused` reasons: `notFound`, `ended`, `full`, `paused`, `needsUpdate`, `needsUnlock`, `tooMany`,
  `unreachable`, `invalid`. `ended` answers a code or token for a room that was there but has
  closed or run out of time. `unreachable` answers an `invite` to someone who cannot be notified:
  never registered, notifications off, or they blocked the asker (the relay does not say which). `notFound` answers a wrong code or token, and also any message from a connection
  that is not in a room: a phone that thought it was seated takes its seat back with `rejoin`. A phone treats a reason or a `type` it does not know as something to pass over, so
  the relay can say new things without breaking old apps.
