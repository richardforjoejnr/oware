# Lelu Ludo: nearby play (plan)

Two to four people, each on their own phone, one board, with no router or internet. Phones find
each other through Bonjour over Apple's phone-to-phone Wi-Fi. **Free**, behind the `nearbyPlay`
feature switch. **Empty seats are played by the computer.**

This comes **after Lelu Oware's nearby play** ships. It reuses what Oware's work builds:
- MatchKit;
- `FeatureGate`;
- the real-phone checklist;
- the lessons of the two-phone spike.

The shared design is [MULTIPLAYER.md](../../../docs/MULTIPLAYER.md); Oware's plan is
[NEARBY_PLAY.md](../../lelu-oware/docs/NEARBY_PLAY.md). This file covers what is different for
Ludo. Planned 2026-10-28; nothing is built yet.

## What is different from Oware

| | Lelu Oware | Lelu Ludo |
|---|---|---|
| Phones | 2 | 2–4 (host + up to 3 guests) |
| Empty seats | None | Computer players, run on the host's phone |
| Chance | None | Dice: the **host's phone rolls** every die, and each roll is part of the snapshot |
| Someone drops | Offer to finish against the computer | After 60 s **the computer takes that seat** and the game goes on for the others. If they come back, they get the seat back. |
| Host drops | Both phones hold the game | Each guest can carry on from the same position against computers. Handing the host role to a guest automatically is later. |
| Board | Turned round for the guest | Each phone shows **its own yard nearest the player**: the board is rotated to the seat (needs checking with the art: shadows, text) |

Who rolls is the host's phone, because friends are sitting together and it keeps every phone
identical. If cheat-proof dice are wanted later (for online play with strangers), each phone can
contribute to every roll (commit, then reveal). That changes only how a roll is made, not the match
format: a roll is still a number in the action list.

## What the player sees

1. **Home ▸ Play nearby ▸ Host** or **Join**.
2. **Waiting room (host):**
   - the rules from Settings (Ghana house rules);
   - four colour seats. Guests who join pick a free colour, first come first served;
   - the host fills any empty seat with a computer player (level per seat) or leaves it out;
   - **Start** once at least one guest has joined (2–4 colours in play).
3. **The game:**
   - On your turn you roll and move as today.
   - Everyone else's rolls and moves are animated on every phone: the die is thrown with the host's
     roll, and tokens walk.
   - Names come from the waiting room.
4. **Someone drops:** "Ama is reconnecting…". After 60 s: "The computer is playing for Ama". When
   Ama returns: "Ama is back".
5. **The end:** the usual celebration. **Play again** keeps the same seats if everyone agrees.

## How it fits the code

| Piece | Change |
|---|---|
| `LudoEngine/LudoMatch.swift` (new) | The match format:<ul><li>format version, `matchID`, rules, the colours in play, who sits where (person or computer), and `actions`: `.roll(Int)`, `.move(Move)`, `.computerTakesOver(PlayerColor)`, `.playerReturns(PlayerColor)`, `.resign(PlayerColor)`;</li><li>`state()` replays it through `GameState`, refusing anything illegal, as `OwareMatch` does.</li></ul> |
| `LudoEngine` (new) | `LudoIntent`: `.roll`, `.move(Move)`, `.resign`, `.playAgain`. The host turns `.roll` into `.roll(n)` from its `DiceSource`. |
| `Game/GameStore.swift` | `Seat` gains `.remote(name:)`. `GameSetup` is otherwise unchanged. |
| `Game/LudoSession.swift` | Takes an optional `MatchLink`.<ul><li>**Host:** runs computer seats (`runComputerTurns` as today) and records their actions in the match.</li><li>**Guest:** never rolls or runs the computer; it animates the actions in each snapshot.</li><li>`roll()` / `play(_:)` on your seat send an intent.</li></ul> |
| `Game/Seating.swift` | `NearbySeating`: free colours, a guest's pick, a computer per empty seat, can start. Pure and tested. |
| `Board/BoardView.swift` | A `bottomColour` rotation so each phone's own yard is nearest. |
| `Screens/NearbyView.swift` (new) | Host / Join / waiting room / name / local-network help. |
| `Support/Features.swift` (new) | `nearbyPlay: .free`, `online: .off`, and `nearbyFourPlayers: .free` (so 3–4 phones could be sold separately later, if ever). |
| `project.yml` | `NSLocalNetworkUsageDescription`, `NSBonjourServices: [_leluludo._tcp]`. |
| `docs/lelu-ludo/privacy.md`, `STORE_LISTING.md` | The nearby play paragraph, and the review note. |

Online play later works the same way as for Oware:
- `GameCenterTransport`, with `via: .online`;
- an `online` entry switched to `.unlock(...)`;
- real-time Game Center (`GKMatch`) suits Ludo better than turn-based, because four people take
  short turns.

## Order of work: tests first

Each step is one PR; the tests are committed first and fail. Hidden (`nearbyPlay: .off`) until the
last step.

### Step 1: `feat(engine): a Ludo match format for playing on several phones`
Tests first (`LudoEngineTests/LudoMatchTests.swift`, Linux):
- a scripted 4-colour game replays to the same `GameState` as playing it directly;
- refused:
  - a roll when a move is due;
  - a move not in `legalMoves()`;
  - a die face of 0 or 7;
  - a roll by the wrong colour;
- three sixes in a row are undone exactly as in `GameState`;
- `.computerTakesOver` / `.playerReturns` change who sits where, but not the board;
- a newer format is refused;
- a long 4-player game encodes under 64 KB;
- `.playAgain` keeps the seats, with a new `matchID`.

### Step 2: `feat(ludo): seats for nearby play`
Tests first (`LeluLudoTests/NearbySeatingTests.swift`):
- two guests cannot take one colour;
- the host's colour is fixed once a guest has joined;
- empty seats become computers at the chosen level;
- start needs at least one guest;
- a fifth phone is refused;
- `nearbyFourPlayers: .off` limits the room to 2 phones (proves the switch works).

### Step 3: `feat(ludo): play a game on several phones`, the session
Tests first (`LeluLudoTests/RemoteGameTests.swift`, a host and three guest `LudoSession`s on
`LoopbackTransport`, with scripted dice):
- every phone shows the same board after every action of a full game;
- guests never roll;
- a computer seat plays only on the host;
- you cannot act on another colour's turn;
- a guest dropping for 60 s hands its seat to the computer, and its return takes it back mid-game;
- the host dropping lets each guest finish against computers;
- Play again keeps the seats.

### Step 4: `feat(ludo): nearby play screens`
Tests first:
- **XCUITest with `--nearby-demo`:**
  - three pretend players join, one picks a colour, an empty seat becomes the computer;
  - a scripted game plays to a win;
  - the board is rotated to the seat;
  - VoiceOver labels.
- **Maestro:** `nearby-demo.yaml`.

### Step 5: `feat(ludo): turn on nearby play`
- `nearbyPlay: .free`;
- the privacy page, the review note, What's New.

Real-phone checklist (as Oware's, plus):
- [ ] Four phones (iPads count): a whole game with no router, then Play again.
- [ ] Three phones + one computer seat; two phones + two computer seats.
- [ ] A guest walks out of range mid-game: the computer takes over, the guest returns and plays on.
- [ ] The host leaves: each guest can finish against computers.
- [ ] Every phone shows the same die face for every roll.

## Still to decide (later, not blocking)

- **More than one person per phone:** can one phone hold two seats (pass & play within a nearby
  game)? Not in v1.
- **Turn timer:** if someone stops playing without dropping (put the phone down), should the
  computer roll for them after a while?
- **Board rotation:** does it suit the board art, or is a fixed board with "You" marked better?
  Check with mock-ups first.
