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

**Stage 2, computer opponents, is built** (`LudoAI`, branch `feat/lelu-ludo-ai`, PR after #62 merges):
heuristic choice per level (Novice to Grandmaster): kicks by the victim's progress, home, safe lane,
entering, danger at the landing square (forward, entry and back-kick reach), escaping, walls;
Grandmaster also weighs all its tokens' exposure after the move. Slips 50/20/5/0%. 8 tests.

**Stage 3, the playable app: first part built** (branch `feat/lelu-ludo-app`): `LudoSession` (seats,
dice, computer turns, pass & play, saves), the board drawn from the grid in flag colours, tokens with
44 pt targets and VoiceOver labels, the die, a home menu (computer 1–3 opponents at a level, pass &
play 2–4). Launch flags `--reset-state --dice=6,4 --start-game --fast`. 8 unit + 3 UI tests including
the accessibility audit.
Still to do in stage 3: move animation along the path, choosing a back kick when a forward move is
also possible (today a token tap plays the forward move), sounds and haptics, house-rule settings,
a casual-player balance test (as Oware's), the macOS app job in `ludo-ci.yml` (commented out there).

**PR order:** #62 (stage 1 + shared pipelines) → stage 2 (`feat/lelu-ludo-ai`) → stage 3
(`feat/lelu-ludo-app`); each PR is opened against `main` once the one before is merged, so none is
closed when its base branch is deleted. Waiting on the owner: answers on home kick, side
kick and Labourer; art per `ART_DIRECTION.md`; confirm black (not blue) tokens and the star-as-6 die.

## 2026-10-04

- Merged: #62 (stage 1 + shared CI), #63 (stage 2 AI), #64 (per-app versions), #65 (stage 3 app;
  Lelu Ludo CI now builds and tests the app on a simulator).
- Open: **#66** Ghana Classic kicks, move choice, step-by-step moves (green); **#67** stage 4 rules
  settings, sound and haptics, balance test (merge after #66).
- **Next: stage 5, release** — the lesson, Game Center, tip jar, privacy and support pages under
  `docs/lelu-ludo/` (served on leluoware.com), App Review checks for this app, TestFlight and App
  Store workflows with Lelu Ludo's own release tags, the owner's art (none in the repo yet; see
  ART_DIRECTION.md: the app icon first).
