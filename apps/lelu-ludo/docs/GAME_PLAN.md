# Lelu Ludo — game plan

Ludo as it is played in Ghana, on a carved wooden board in the colours of the flag. The second
"Lelu" game, built in the same monorepo as Lelu Oware: same principles (`../../../docs/DESIGN_PRINCIPLES.md`),
same test pyramid, same release pipeline. Started 3 October 2026.

## Decisions (owner, 2026-10-03)

| Topic | Decision |
|---|---|
| Name | **Lelu Ludo** (bundle `com.richardforjoe.leluludo`) |
| Colours | Ghana's flag: **red, gold, green, black** (black with a brass rim on dark wood). Black star at the centre |
| Seating | Clockwise from top left: red, gold, black, green (as in the board art; black takes the art's blue corner) |
| Version 1 | 1 player against 1–3 computer opponents, and pass & play for 2–4 on one phone. Tips, Game Center, no ads. Online later (paid, host pays), as for Oware |
| Default house rules | Forward kick, **back kick**, a kick or a token home earns a roll, three sixes forfeit, **blocks of two** |
| Assets | The owner makes them (ChatGPT); `ART_DIRECTION.md` lists what is needed |

## Rules

Always on (all three sources agree: Masters of Games, African Delight, Tablelity "Ghana Ludo"):

- 2–4 players, 4 tokens each, in the yard at the start.
- A **6** brings a token out onto the colour's start square. A 6 also gives **another roll**.
- Tokens move clockwise by the roll: 51 track squares from the start, then the colour's own 5-square
  home lane, then home. **Home needs the exact roll.** The home lane is private.
- **Forward kick:** ending a move on a lone opponent sends it back to its yard.
- No legal move: the turn passes (a 6 still rolls again).
- First player with all four tokens home wins.

House rules (Settings switches; defaults in bold):

| Rule | Default | What it does |
|---|---|---|
| Back kick | **on** | If an opponent is exactly the roll *behind* one of your tokens, that token may move back onto it and kick it home instead of moving forwards. Never back past your own start. A characteristically Ghanaian rule |
| Kick or home earns a roll | **on** | Kicking someone home, or bringing a token home, gives another roll |
| Three sixes forfeit | **on** | A third 6 in a row ends the turn and undoes everything played in it |
| Stacking | **wall** | Two or more of your tokens on a square: **wall** (no opponent passes or lands), or **safe** (cannot be kicked, can be passed), or **not allowed** (one token per square, the Ghana Ludo sheet's rule) |
| Safe start squares | off | Nobody can be kicked on a start square (another Ghana ruleset says no square is safe) |
| Safe star squares | off | The four stars half-way along the arms are safe |
| Entry rolls | **6** | A gentler game lets a 1 bring tokens out too |

### Proposed, needing the owner's confirmation before they are built

These are recognisably Ghanaian but are played several ways. The engine is built so each slots in as
another `RuleSet` switch. For each: the rule as proposed, and the questions to answer.

- **Home kick.** An opponent in their home lane is not safe: with the exact roll, a token passing
  that lane's entrance may turn into it and kick them; the attacker must then come back out.
  *Questions:* which tokens may turn in (any passing token, or only one that would otherwise pass the
  entrance this move)? Does it come back out by moving backwards along the lane on later rolls, or
  is it put back on the entrance square at once? Can it be kicked while it is in someone else's lane?
- **Side kick.** A token facing an opponent across an arm (the other outer column of the same arm,
  with the home lane between them) slides across and kicks it. *Questions:* which roll does it take
  (any roll, the roll matching some count, a 1)? Forwards side and backwards side, or one only?
  Does the kicker end on the opponent's square?
- **Labourer** (advanced, optional). When a player is down to one active token, an opponent can
  capture it and use it as their own until its owner frees it by rolling a 6. *Questions:* exactly
  when can it be taken (by a kick? by landing beside?), who moves it, can it be kicked while held,
  and what happens to it when freed?

## Stages

Each stage: write the tests, implement, test, improve, then move on. Nothing from a later stage starts
before the earlier one is green and merged.

1. **Rules engine** (`packages/LudoEngine`) — *done in the first PR.* Board geometry, turns, dice,
   forward and back kicks, bonus rolls, three sixes, stacking modes, safe squares, entry rolls,
   winning, validated saves. Tests: see "Test pyramid".
2. **Computer opponents** (`LudoAI` target in the package). Levels like Oware's ladder (Novice to
   Grandmaster): heuristic move choice (kick, escape danger, enter on 6, race, protect a wall, use
   back kicks), slips for the lower levels, no lookahead needed for a dice game at first. Tests:
   every choice is legal; stronger levels beat weaker ones in seeded tournaments; a balance test
   with a simulated casual player, as Oware's `BalanceTests`.
3. **Playable app** (`apps/lelu-ludo`). Home menu, set-up (colours, opponents, rules), the board drawn
   from `Board`'s grid (SpriteKit, as Oware), dice roll with the cup, token selection, move preview,
   animations, sounds, haptics, VoiceOver (every square and token described), pass & play hand-over.
   Tests: app unit tests (session, settings, saves), UI tests (start a game, roll, move, kick, win
   with scripted dice via a launch flag), accessibility audit on every screen, Maestro and Appium
   flows. `ludo-ci.yml` gains the macOS app job; `e2e` gains a Ludo workflow.
4. **The proposed house rules** above, once the owner has answered the questions: each one test-first,
   added to the reference implementation as well, behind a Settings switch.
5. **Polish and release:** art from the owner, the lesson ("New here?"), Game Center, tips, privacy
   and support pages on leluoware.com (`docs/lelu-ludo/`, served by the existing site), App Review
   readiness (the same checks), TestFlight and App Store workflows copied for this app.
6. **Later:** online play (Game Center turn-based, paid, host pays), as planned for Oware.

## Test pyramid

As for Lelu Oware: most tests are fast engine tests, a few slow ones at the top.

| Layer | Lelu Oware has | Lelu Ludo stage 1 has |
|---|---|---|
| Hand-checked rule scenarios | ~70 (`GameStateTests`, `NamNamTests`, `NamNamRoundTests`) | `RulesTests`: entry on 6, gentle entry, moving, forward kick, kick bonus, exact home, winning, illegal moves; back kick and its limits, wall, safe stack, one-per-square, three sixes (with and without the rule), no bonus when off, safe start |
| Board geometry | — | `BoardTests`: 52-square loop, starts, lanes join the track and the centre, every progress has a square |
| Independent reference implementation | Abapa 2,000 games, Nam-Nam several suites | `ReferenceTests`: a second Ludo written square by square must agree on every legal move, position, turn and winner, roll by roll, in 560 random games under 7 rule sets. Proven to catch a planted off-by-one in the wall check |
| Invariants over random games | `RuleInvariantTests` | `InvariantTests`: tokens in range, no two colours on an unsafe square, one-per-square holds, moves do what they say and kicks go to the yard, turn order, walls never passed, three sixes undo, determinism, saves resume at any point |
| Damaged saves | `CorruptSaveTests` | `CorruptSaveTests`: good saves load, 10 kinds of damage refused, random damage never crashes (Apple platforms; Linux's JSON parser traps on its own) |
| AI | `AIPlayerTests`, `BalanceTests`, fuzz | Stage 2 |
| App unit, UI, accessibility, E2E | yes | Stage 3 |

The pyramid already found one bug in stage 1: saves refused a run of three or more sixes under rules
without the three-sixes rule.

## Pipelines

- `ludo-ci.yml` ("Lelu Ludo CI"): only for `apps/lelu-ludo/**`, `packages/LudoEngine/**`. The engine
  runs on Linux in Apple's `swift:6.0` container (a tenth of a macOS runner's cost on a private repo).
- Lelu Oware's `ci.yml` and `e2e.yml` now run only for Oware's app, its packages, scripts and its
  site pages; `site-ci.yml` tests the website's infrastructure.
- `make engine-test` at the root runs every package, LudoEngine included.

## Art direction notes (from the owner's mock-ups, 2026-10-03)

Keep: the wooden tray with brass corners; cream painted tracks with the colour lanes; the black star
in the centre; the dice cup with the brass star; a carved band of zigzags. Change or check:

- **Blue → black tokens** (the chosen colours), with a brass rim so they read on dark wood.
- **The symbol on the box and cup** (four looped knot): it looks like *Mpatapo*, the knot of
  reconciliation, a fitting sign for a game of kicking each other home and playing on as friends.
  Confirm it in the cultural review before it ships (design principles: Adinkra only with meaning).
- **Dice:** the flag on one face and the star on another are lovely, but a die needs six readable
  faces. Proposal: the black star replaces the six pips (a 6 is the roll that matters most in Ludo);
  no flag face.
- **Menus:** "Play Online", "Shop", "Profile" and the robot icon are not in v1 (online is later; there
  is no shop, only optional tips; opponents are people's names, not robots). AI-made images often
  garble text (one mock-up reads "Lnou"); all text is drawn by the app, never baked into art.
- **Kente** cloth as a background accent, not on the board itself (as in Oware).
