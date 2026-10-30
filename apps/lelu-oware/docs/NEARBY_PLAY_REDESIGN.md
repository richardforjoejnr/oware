# Lelu Oware: nearby play, the redesign (owner review, 2026-10-30)

The owner tried step 5 (PR #103) on two iPhones and wrote this brief, with mockups and a carved
wood UI kit. It replaces the screens in [NEARBY_PLAY.md](NEARBY_PLAY.md) §"What the player sees";
the engine, MatchKit and the session from steps 1–4 stay. Start here when picking nearby play
back up.

- Mockups: `art/nearby/mockups/` (names below). The kit: `art/nearby/ui-kit.png`.
- Assets cut from the kit: `art/nearby/pieces/` (`art/nearby/make_nearby.py`; `--install` puts
  them in the asset catalogue once a screen uses them).

## 1. The owner's first notes (and what was decided)

| Note | Decision (brief §3–§7) |
|---|---|
| Both players can be on different rules; the host should set them. | The creator picks the rules on the Start screen; they travel with the game and the joiner sees them before joining. (Already true in code: the guest plays the host's `OwareMatch.rules`; but the host can only pick them in Settings, and nothing says so.) |
| Maybe no host / join: whoever starts first hosts, the other joins. | One screen. It lists games nearby by itself while open; **Start nearby game** makes yours. No "Host", "Join mode", "client" anywhere in the UI. Internally one phone stays authoritative. |
| The name should be the phone's name, or a default. | iOS 16+ gives apps only "iPhone" (the real name needs an entitlement Apple rarely grants). Use a saved **Nearby name**, default **Oware Player**; never a prompt in the way. |
| If either leaves, offer rejoin or the computer. | Connection lost sheet (Keep waiting / Continue vs Computer / Leave), automatic reconnect, a **Rejoin** card when they come back, and a separate "left the game" path for a deliberate leave. |
| Should the other player always start (to be sure both are in), or keep the choice? | Keep the choice (Me / Other player / Random). A **Ready** handshake on both phones, not the turn order, makes sure both are in. |

## 2. The brief

### Principle
Nearby play should feel like sitting down beside someone with an Oware board, not configuring a
network session. No Host, Client, Advertise, Browse or Session in the player's words.

### Screens (mockup in brackets)

**A. Nearby lobby** (`a-lobby.jpg`). Title *Play nearby*; *Two phones. One game. No internet
needed. Stay close and keep Wi-Fi on.* Rules row (*Nam-Nam rules ›*), **Who starts**: *Me · Other
player · Random*, Nearby name, primary **Start nearby game**, then **Games nearby**, found
automatically while the screen is open, as wooden cards. Empty: *No games nearby yet* / *Ask your
friend to start a nearby game.* Footer link: *How nearby play works*.

**B. Your game is ready** (`b-game-ready.jpg`). *Your game is ready* / *Looking for another player
nearby…* with the six-seed searching indicator, a small card (rules; starter as *You* / *Other
player* / *Random*; your nearby name), **Cancel**. A connection alone never starts the game.

**C. Game found** (`c-game-found.jpg`). Card: *Richard's game* (or *Nearby Player*), *Nam-Nam ·
Richard starts* (from this phone's side: *You start* when the creator chose Other player),
**Join game**. Link: *Can't find each other?*

**D. Ready to play** (`d-ready-joined.jpg`, `d-ready-both.jpg`). Both phones: a tile per player
(name, Connected, Ready seal), the rules and who starts, **Ready**. Begin only when both phones
are connected, hold the same configuration, have acknowledged the same initial state, and both
pressed Ready.

**E. Connection lost** (`e-connection-lost.jpg`). Board stays, dimmed, input frozen. Sheet:
*Connection lost* / *Trying to reconnect to Richard…* (reconnecting indicator), **Keep waiting**,
**Continue vs Computer**, **Leave game**. Automatic reconnect for about 30–60 s. On reconnect:
compare game ID, move number and state hash, send the latest state if needed, resume exactly.

**F. Rejoin** (no mockup; `nearby-card-rejoin` in the kit). *Richard is back* / *Round 3 · 7–5
houses* / **Rejoin game**: restores the human-v-human game.

**Deliberate leave.** The other phone shows *Richard left the game* with **Continue vs Computer**
and **Leave game**. Never "reconnecting" for someone who left.

**In the game** (`game-connection-header.jpg`, `game-with-opponent-strip.jpg`): a *Nearby play*
header with the two-phones-and-seeds link (it doubles as the connection state), names on the
plaques, *Richard's turn*.

**Help.** Replace the long "Finding each other" sheet with three steps (*Keep both phones close —
no internet is needed* / *Start on one phone — tap Start nearby game* / *Join on the other —
choose the game when it appears*) and a *Having trouble connecting?* link for Local Network and
Wi-Fi.

### Who starts
Stored as `creatorStarts`, `joiningPlayerStarts`, `random` (random is settled by the creator's
phone before the game is offered, so both phones agree). Shown per phone: *You start*, *Richard
starts*, *Random start* (until settled).

### Names
1. The Nearby name saved in Lelu Oware (Settings: **Nearby name**, *Shown only to players near
   you.*, default **Oware Player**).
2. A suitable discoverable name if one exists. Suggestion: the Game Center alias, which the app
   already signs in for.
3. **Nearby Player**.

Never "Me" or "You" as a stored name ("Me's phone has gone"). Two players with the default name
need telling apart: suggest the side colour (*Oware Player · red*).

### What the creator's phone decides
Rules, starting player, initial board, round, territory, any random seed, and the game ID. The
joining phone acknowledges them before play. After each move both phones hold the whole game,
and the sync carries the move number and a state hash so reconnecting and "continue vs computer"
are safe.

### Permissions
`NSLocalNetworkUsageDescription`: *Lelu Oware uses your local network to find another nearby
player and play directly between your phones.* `NSBonjourServices`: `_leluoware._tcp` (in
`project.yml`). No permission prompt before the player opens Play nearby.

### Look
Same visual language as the rest of the game: dark cocoa, carved Ghanaian hardwood, cream type,
restrained gold for the player and red for the opponent, tiny red / gold / green inlays. No grey
iOS cards, no networking blue, no Wi-Fi-tech look. The connection is two sides of a board coming
together.

### Acceptance criteria
- Different local rule selections can never create different game rules.
- The creator's rules are sent and accepted before play.
- The UI never needs the words Host or Client.
- No first move until both phones have acknowledged the same initial state.
- Either player may start, by the creator's choice.
- Disconnecting does not end the game at once.
- A disconnected player can rejoin the same state.
- The remaining player can hand the opponent's side to the computer.
- The game state stays deterministic after reconnecting.
- Names work when iOS only says "iPhone".
- Every nearby control matches the wood / Ghana visual system.

## 3. Where the code is now (PR #103) against the brief

| Brief | Now | Work |
|---|---|---|
| One screen, auto-discovery, Start nearby game | Host / Join buttons; Join starts browsing (`NearbyView`, `NearbyLobby.browse`) | Lobby browses on appear; `host(…)` becomes Start. `LiveNearbyNetwork` can browse and advertise at once; stop browsing once your game is listed. |
| Rules on the Start screen | From Settings (`settings.rules`); listing shows them (`info["rules"]`) | Rules picker on the lobby; keep the TXT record. Guest already plays `OwareMatch.rules`. |
| Me / Other player / Random | `NearbyLobby.Starter` .me/.them/.random titled You/Them/Either; random settled on the host | Rename to `creatorStarts / joiningPlayerStarts / random` and the copy; put the starter in the TXT record so the card can say *Richard starts* / *You start*. |
| Ready handshake | Host taps **Play** on "Ama wants to play"; the game starts at once on both phones | Add `ready: Set<Player>` (and the guest's acknowledged state hash) to `OwareTable`; `OwareRoomRules.applying` refuses `.play` until both are ready and the hashes match. Screen D replaces the Play / Not now card (the creator keeps a way to say no). |
| State hash, move number | `OwareMatch` is the move list; every phone replays it with the engine (deterministic, tested; whole game under 64 KB) | Keep the move list as the truth (don't switch to sending board snapshots). Add `stateHash` (of the replayed `GameState`) to what is checked on ready and on reconnect. |
| Nearby name, default Oware Player | Asked once in a prompt; kept as `nearbyName`; editable in Settings | Drop the prompt; default *Oware Player*; Settings label *Nearby name* + *Shown only to players near you.*; Game Center alias as a suggestion. |
| Connection lost sheet | "Reconnecting to Ama…" banner after 6 s quiet; after 60 s an overlay with Finish against the computer / Leave | Sheet at once (board dimmed, input frozen) with Keep waiting / Continue vs Computer / Leave. |
| Automatic reconnect | Only works while the TCP connection survives (quiet spells). `Room.reconnect(over:)` and the rejoin token exist in MatchKit but the app never makes a new connection | The guest keeps browsing for the same game (match ID in the TXT record) and calls `reconnect(over:)`; the creator keeps advertising while a seat is reconnecting. The host already resends the match to a seat that comes back (#103). |
| Rejoin card / restore HvH after Continue vs Computer | `finishAgainstComputer` stops the room for good | Keep the room listening after switching to the computer; if the other phone returns, offer *Richard is back · Rejoin game* and hand the side back (computer's moves stay played). |
| Deliberate leave | `bye` → `seatLost`, same as timing out ("Ama's phone has gone") | New `RoomEvent.left(seat:)` for `bye`, separate from `seatLost`; copy *Richard left the game*. |
| Help | Five-bullet "Finding each other" sheet | Three steps + *Having trouble connecting?* |
| Local Network text | *Lelu Oware looks for phones near you so two people can play one game, each on their own phone. Nothing leaves the room.* | Use the brief's text. |
| Nearby play header in game | Opponent strip only | Header with `nearby-link` showing the connection state. |

## 4. Assets (`art/nearby/pieces/`, from `ui-kit.png`)

| Piece | For | Notes |
|---|---|---|
| `nearby-icon` | Home ▸ Play nearby (NearbyPlayIcon) | Replaces the borrowed `wood-people` glyph. |
| `nearby-link` | Game header, ReconnectingIndicator | Pulse the dots in code, or draw them with the pips. |
| `nearby-seed-ring` | SearchingIndicator | Turn slowly. Must be still in test launches (see §6). The kit's seeds are mottled; the board's are `seed1…8`. Consider drawing the ring from the board's seeds instead. |
| `nearby-seal-ready`, `-waiting` | ReadySeal | |
| `nearby-pip-*` | Connection status: searching, connected, waiting (reconnecting), lost, calling, idle | Mind colour-only meaning: pair each pip with a word. |
| `nearby-card-game` | NearbyGameCard | Stretch with cap insets (about 40 pt each end); the play button is baked in, so either keep it as the Join hit area or cut the frame alone. |
| `nearby-card-rejoin` | RejoinCard | Arrow baked in. |
| `nearby-tile-gold`, `-red` | PlayerConnectionTile | Bowl + pips baked in; text goes in the inset panel. |
| `nearby-chip-rule`, `-start` | RuleChip, StartChip | |
| `nearby-sheet` | ConnectionLostSheet | Its three buttons are baked in; for real buttons use the frame only, or the `nearby-button-*` pieces over a plain carved panel. |
| `nearby-button-gold`, `-wood`, `-red`, `-small` | Primary, secondary, leave, small | Resizable with cap insets. |
| `nearby-band` | Divider | Red, gold and green inlays. |

The mockups show more carved icons (rules book, person, pin, computer, leave, no-Wi-Fi) that are
not in the kit; `wood-book` exists already, the others are still to make or to draw with SF
Symbols in the wood colours.

### Things to settle in the mockups
- `d-ready-both.jpg` shows the rules row twice.
- `d-ready-joined.jpg` gives the joining player a Who starts picker; the brief says only the
  creator chooses.
- `e-connection-lost.jpg` shows a player called "You" with an "M" badge, the naming bug the brief
  warns about.
- Colours: the brief says gold for the player and red for the opponent. Today colour follows the
  side (South gold, North red), so the joiner is red on their own phone. Per-phone colour reads
  better ("I'm always gold"); per-side colour lets players say "red's turn" across the table.
  Pick one. The mockups draw the joiner's own row on the left; since #103 your own row sits on
  the right, nearest your hand.

## 5. Testing notes carried from step 5

- **Sowing speed.** Each phone had its own Sowing speed, so boards drifted. #103 makes both sow
  at the slower (`OwareTable.paces`). Not yet seen on both real phones: "iPhone (87)" couldn't be
  reached when the fix was installed.
- **Reduce Motion** on one phone shortens captures by about 0.1 s each (`BoardScene.lift`); take
  it out of shared timing if drift remains.
- **Spinners in UI tests.** An animated view keeps the app from settling and XCUITest waits 60 s
  before every step. Any new indicator (seed ring, pulsing link) must be still under
  `LaunchOptions.fastAnimations` (see `WaitingMark`).
- **Saved name between UI tests.** A name saved by one test sometimes survived the next test's
  `--reset-state`. It couldn't be reproduced outside the test runner, so the tests type a name only
  when asked. Dropping the prompt (above) removes the problem.
- **Two real phones.** Debug builds show nearby play with `-nearbyPlay YES`
  (`xcrun devicectl device process launch --device … com.richardforjoe.oware -- -nearbyPlay YES`).
  Both phones need the same build: the shared game data changed in #103.

## 6. Suggested order (each a PR, tests first, still behind `nearbyPlay: .off`)

1. **Protocol:** ready handshake + state hash in `OwareTable`, `RoomEvent.left`, starter stored as
   `creatorStarts / joiningPlayerStarts / random`, game ID and starter in the TXT record.
2. **Lobby:** one screen with discovery, Start nearby game (rules, who starts, name), Your game is
   ready, game cards, Ready to play; default names; new help sheet and Local Network text.
3. **Connections:** Connection lost sheet, reconnect over a new connection, Rejoin card,
   deliberate leave, rejoin after Continue vs Computer.
4. **Look:** install the kit pieces, the components (NearbyPlayIcon, NearbyGameCard,
   PlayerConnectionTile, RuleChip, StartChip, ReadySeal, SearchingIndicator,
   ReconnectingIndicator, ConnectionLostSheet, RejoinCard), the in-game header.

Then step 6 of NEARBY_PLAY.md (turn it on).
