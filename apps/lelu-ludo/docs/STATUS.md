# Lelu Ludo — status and hand-off

> For a new session: read this, then [GAME_PLAN.md](GAME_PLAN.md). Work goes in stages; finish one
> (tests, implement, test, improve) before starting the next.

## Now (2026-10-03)

**Stage 1, the rules engine, is built** (`packages/LudoEngine`, branch `feat/lelu-ludo-foundation`).
- `Board`: the 15×15 cross, 52-square track, starts, lanes, the 3×3 centre, star squares.
- `GameState`: roll / legal moves / apply; forward kick, back kick, bonus rolls, three sixes,
  stacking (wall, safe, not allowed), safe start and star squares, entry rolls, winning; validated
  saves.
- 34 tests in 7 suites (~1 min debug), all passing on macOS and on Linux (`swift:6.0`): scenarios,
  board geometry, an independent reference implementation (560 random games, 7 rule sets), invariants,
  damaged saves.
- The app is the template scaffold (`make new-app`), not yet using the engine.
- CI: `ludo-ci.yml` (engine on Linux); Oware's workflows filtered to Oware.

**Next: stage 2, computer opponents** (see the plan). Waiting on the owner: answers on home kick, side
kick and Labourer; art per `ART_DIRECTION.md`; confirm black (not blue) tokens and the star-as-6 die.
