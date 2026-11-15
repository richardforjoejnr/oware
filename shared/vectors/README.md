# Shared examples

JSON examples that every side of a wire format is tested against. They are the contract: the
Swift apps, the relay on AWS (`apps/lelu-play` in the AWS repo) and, later, the Android apps each
have a test that reads these files. Nothing here is loaded by an app at run time.

| Folder | What | Tested by |
|---|---|---|
| [`room-v2/`](room-v2/README.md) | What phones in one game send each other (room protocol, version 2) | `packages/MatchKit` (`RoomVectorTests`), Lelu Oware (`OwareTests/RoomVectorTests`) |
| [`relay-v1/`](relay-v1/README.md) | What a phone and the relay send each other (version 1) | `packages/MatchKit` (`RelayMessageTests`); the relay's contract tests, from a copy that records the commit it was taken from |

Rules:

- **Never edit an example to make a test pass.** Phones in people's hands already speak these
  formats. A change that old apps cannot read is a new version in a new folder (`room-v3/`). A
  phone refuses every room protocol version but its own, so only the current folder is kept.
- Adding an example for something that is already sent is fine. The tests count the files, so say
  in the test what the new one means.
- The plan is [docs/ONLINE_PLAY.md](../../docs/ONLINE_PLAY.md) (§5, Messages).
