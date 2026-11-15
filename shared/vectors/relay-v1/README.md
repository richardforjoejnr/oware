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
- `refused` reasons: `notFound`, `full`, `paused`, `needsUpdate`, `needsUnlock`, `tooMany`,
  `invalid`. `notFound` answers a wrong code or token, and also any message from a connection
  that is not in a room: a phone that thought it was seated takes its seat back with `rejoin`. A phone treats a reason or a `type` it does not know as something to pass over, so
  the relay can say new things without breaking old apps.
