# Lelu Oware — Project status & handoff

> **For a new Claude Code session:** read this file first, then `docs/GAME_PLAN.md` and
> `docs/PIPELINE.md`. Resume from "Next steps" below. Last updated: 2026-09-23 (evening).

## Where things are

- **Branch:** `chore/scaffold-project` → **PR #1** https://github.com/richardforjoejnr/oware/pull/1
  (not yet merged; owner merges). `main` is protected: PR + three required checks.
- **Plan:** `docs/GAME_PLAN.md` v0.2. Owner decisions recorded in §7. The plan as a whole still
  needs the owner's explicit "approved" before Milestone 1 (rules engine) starts.
- **Owner decisions so far:** title *Lelu Oware*; free + one-time IAP, no ads; online play deferred
  to v1.1; Swift app with TypeScript for tests/tools; concept art via connected Adobe/Canva tools;
  owner has a paid Apple Developer account; owner reviews cultural content himself.

## Done (all verified green in CI unless noted)

| Area | What exists |
|---|---|
| Project | `project.yml` (XcodeGen) → SwiftUI app `Oware`, iOS 17+, iPhone+iPad, bundle `com.richardforjoe.oware`, display name "Lelu Oware". `Oware.xcodeproj` is generated, not committed (`make project`). |
| Engine | `Packages/OwareEngine` — stub `GameState` (initial 4×12 = 48 seeds) + Swift Testing test. `swift test` works with Command Line Tools only. |
| App | Placeholder home screen with accessibility ids `home-title`, `home-seed-count`. |
| Tests | `OwareTests` (unit), `OwareUITests` (XCUITest), `.maestro/flows/smoke.yaml` (Maestro), `e2e/` (TypeScript Appium + WebdriverIO v9, spec `specs/home.spec.ts`, helpers `helpers/board.ts`). |
| CI | `.github/workflows/ci.yml` (engine + app build/test), `e2e.yml` (Maestro job + Appium/TS job), `testflight.yml` (merge to main), `release.yml` (GitHub Release → App Store Connect). Signed workflows skipped until repo variable `SIGNING_READY=true`. |
| Signing/upload | fastlane lanes `test`, `beta`, `release` with match (private cert repo) + App Store Connect API key. `Gemfile` present. |
| GitHub | Branch protection on `main` (checks: "Engine (swift test)", "iOS app (build + test)", "Maestro flows on simulator"). Environments `testflight` and `production` (production requires owner approval). Variable `SIGNING_READY=false`. |
| Docs | `GAME_PLAN.md` (design + culture + compliance), `PIPELINE.md` (what credentials are needed), `CULTURE_SOURCES.md` (source log), this file. |
| Local Mac | Xcode 27.0 (licence accepted), XcodeGen, xcbeautify, mas installed. Maestro CLI at `~/.maestro/bin` (PATH added in `~/.zshrc`) but **needs Java**. Node 22 + npm present; `e2e/node_modules` installed (Appium 3, xcuitest driver 12). |

## Verified locally on the owner's Mac (2026-09-23, 21:45)

- Xcode 27.0 licence accepted. `make engine-test`, `make test` (unit + XCUITest on iPhone 18 Pro Max
  simulator) and the TypeScript Appium suite (`make e2e-build` then `cd e2e && npm test`) all pass.
- Maestro still needs Java locally (`brew install --cask temurin`).

## In progress (as of last session)

- CI fixes pushed: Appium/TS job uses `npm install`; Maestro job has a 300 s driver-startup timeout,
  warm-up launch and one retry; the TS job's real root cause (Appium's 15 s `xcrun` SDK probe timing
  out on cold runners, and Appium 2 / driver 9 predating Xcode 26) was fixed in commit 2b8f280 by
  passing the simulator UDID explicitly, warming Xcode tool caches, and upgrading to Appium 3 +
  xcuitest driver 12. **First thing to do: check `gh pr checks 1 -R richardforjoejnr/oware`.**
  If a job is red, read its log with `gh api repos/richardforjoejnr/oware/actions/jobs/<job-id>/logs`.
- Once both E2E jobs are stable, add "Appium + WebdriverIO (TypeScript)" to the required checks on
  `main` (`gh api -X PATCH repos/richardforjoejnr/oware/branches/main/protection/required_status_checks`).

## Blocked on the owner (needs a password or Apple account)

1. ~~Accept the Xcode licence~~ — done 2026-09-23; normal `git`/`python3`/`xcodebuild` work again.
2. Java for Maestro: `brew install --cask temurin`
3. Apple credentials → GitHub secrets, exactly as listed in `docs/PIPELINE.md` §A–B, then set
   repo variable `SIGNING_READY=true`.
4. Merge PR #1.
5. Confirm the meaning/origin of "Lelu" for the Heritage text and store description.
6. Say "plan approved" (or request changes) so Milestone 1 can begin.

## Milestone 1 — DONE (2026-09-23, PR #2 merged)

- `Packages/OwareEngine` now holds three targets: **OwareEngine** (rules), **OwareAI** (search),
  **oware** CLI (`swift run oware selfplay|play|replay`). 42 tests, all green locally.
- Engine: `Player`, `RuleSet` (Abapa default; grand-slam variants forfeit/illegal/captureEndsGame;
  mustFeed; winningSeeds; repetitionLimit), `Move` + notation (A1…B6), `GameState.legalMoves()`,
  `apply(_:) -> [MoveEvent]` (pickUp, sow, skipOrigin, capture, grandSlamForfeited, sweep, gameOver),
  `GameOutcome` / `GameEndReason`, `GameRecord` (notation, replay, states), `endByAgreement()`.
- AI: iterative-deepening alpha-beta negamax, transposition table, captures-first ordering,
  six `Difficulty` levels (depth 1–12, 0.1–3 s budgets, blunder rate at low levels), five
  `Personality` weight sets (balanced, aggressive, hoarder, cautious, trickster), seeded RNG.
  `AIPlayer.analyse` returns move, score, depth, nodes and principal variation (for hints).

## Milestone 2 — DONE (PR #3 merged 2026-09-23)

Verified locally: XCUITest 4/4, TypeScript suite 6/6 (incl. opt-in screenshots), engine 45/45.
- `Oware/Sources/Game/GameSession.swift` — @Observable session: applies moves, awaits the board
  animation, runs the AI on a detached task with a minimum think time, undo (two plies vs AI),
  resign/agreement, JSON persistence via `GameStore` (Application Support/LeluOware/current-game.json).
- `Oware/Sources/Board/BoardLayout.swift` — shared geometry; **horizontal** (landscape/iPad: north store, A1…A6 / B6…B1, south store) and **vertical** (portrait phones: two columns, A up the right, B down the left, south's store on top).
- `Oware/Sources/Board/BoardScene.swift` — SpriteKit: procedural board/houses/seeds, per-seed arc sowing
  with tick sound + haptic, capture pulse + fly-to-store, sweeps, grand-slam red pulse, long-press
  preview (ghost seeds, landing ring, capture tint). `animationSpeed >= 100` = instant (UI tests).
- `Oware/Sources/Board/BoardView.swift` — SwiftUI overlay owning touch + accessibility
  (`house-A1…B6` value "N seeds", `store-A/B`, `board`).
- Screens: `RootView` (home ⇄ game fade), `HomeView` (Continue / Play + level picker / Pass & Play /
  Settings), `GameView` (top bar home+undo, board, `turn-indicator`, transient `hint`), `GameOverOverlay`,
  `SettingsView` (speed, sound, haptics, counts). `Theme` = quiet palette + serif type (§3.2b).
- Support: `Haptics`, synthesised `SoundPlayer` (placeholder until real drum samples in M5), `AppSettings`,
  launch options `--reset-state` / `--fast-animations` (also `-resetState YES` / `-fastAnimations YES`).
- Engine: added `GameState.preview(_:)` → `MovePreview` (path, landing house, captures) + 3 tests.
- Tests rewritten for the real game: XCUITest (4 cases), Maestro smoke (pass & play, sow, undo),
  TypeScript `home.spec.ts` + `game.spec.ts` (sow, empty-house hint, undo).

## Milestone 0 — art direction: first pass DONE (merged with PR #3)

- Research on Ghanaian carvers (Ahwiaa; osese wood; adze/knife/gouge; dye + wax finish;
  hinged boards; "redwood and black dye"; nickernut seeds) is in `docs/ART_DIRECTION.md`.
- Generated with Canva (media IDs recorded in ART_DIRECTION.md §3), processed by
  `scratchpad/assets/process.py` (difference matting for seed alpha, tileable wood, masked pit):
  `Oware/Resources/Assets.xcassets/Board/{wood,pit,rim,hero,seed1…seed8}`.
- `BoardTexture.swift` bakes the slab; `BoardScene` now draws textured board, pits, stores,
  seeds and Adinkra rim. Screenshot verified on iPhone portrait.
- Still to do in art: journey backdrops, app icon, Adinkra UI icon set (vector), lighting pass
  (SKLightNode + normal maps), reduce visible wood tile repeat, real drum audio.
- **Owner:** confirm the Canva AI-content licence position before App Store submission.

## Milestone 3 — DONE (PR #4 merged 2026-09-23)

- Riddles: `Puzzle`/`PuzzleSet`/`PuzzleGenerator` in OwareAI; 60 shipped puzzles in
  `Oware/Resources/Puzzles/puzzles.json` (regenerate with `swift run -c release oware puzzles …`);
  `PuzzleLibrary` (solved tracking in UserDefaults, daily pick); `PuzzlesView` ("Ananse's riddles");
  puzzle mode in `GameSession` (only the solution counts; wrong taps leave the board unchanged).
- Learn: `Tutorial.steps` (7 steps: welcome, sowing, capturing, chains, grand slam, feeding, winning),
  tutorial mode restricts the learner to the required move; Next / Play controls under the board.
- Rules & heritage: `HeritageView` with Rules and Heritage tabs (hero image, "it is said" phrasing).
- Home rows: Learn, Riddles, Rules & heritage. Tests: 5 puzzle tests, 6 XCUITests, screenshot spec
  covers home, board, riddles, puzzle, tutorial, rules, heritage.
- Open polish: seed-count labels touch the rim band in portrait; store labels could sit inside the
  store; puzzle hints (Nyansapo) not yet implemented; Journey (M4) next.

## Milestone 4 — DONE pending review (branch `feat/journey`, PR #5)

- `Journey.swift`: 8 chapters (Kumasi, Bonwire, Lake Bosomtwe, Techiman, Cape Coast, Makola/Accra,
  Ho/Volta, Tamale) × 3 opponents with region-appropriate names, roles, greetings, difficulty ramp
  Beginner→Grandmaster and a personality each. Stars: win 1★, ≥28 seeds 2★, ≥32 seeds 3★.
  `JourneyProgress` persists stars; a chapter unlocks when every opponent in the previous one is beaten.
- `GameMode.journey(chapter:opponent:)`; greeting shown as a hint at match start; game-over overlay
  shows stars and "Next: <opponent>". `JourneyView` lists chapters/opponents. Home row "Journey".
- One-time purchase (StoreKit 2): `StoreManager` (product `com.richardforjoe.oware.fulljourney`,
  entitlement check, restore), `UnlockView`, chapters 3–8 gated (`JourneyProgress.requiresPurchase`),
  local `Oware/Resources/Products.storekit` wired into the scheme for simulator testing, `--unlock-all`
  launch flag for tests/screenshots. **Owner:** create the same product ID in App Store Connect.
- App icon in `AppIcon.appiconset` (1024², from Canva media `MAHWDmM5VRg`). `docs/PRIVACY.md` drafted
  (needs a support email and hosting, e.g. GitHub Pages).
- Hint button (`btn-hint`, lightbulb for now; Nyansapo icon later): `AIPlayer.analyse` depth 8 / 0.9 s
  shown as the landing preview for ~2 s. Board polish: store counts behind seeds, thinner rim,
  larger wood tile, Reduce Motion → instant sowing, grand-slam convention in Settings.
- `docs/APP_STORE.md`: listing copy, keywords, IAP metadata, privacy label answer, screenshot plan.
- Not yet: cosmetic unlocks (boards, seed sets, Kente borders), chapter establishing shots, achievements,
  real drum audio, Nyansapo/Sankofa vector icons, localisation, App Store screenshots at required sizes.

## In flight on 2026-09-24 (read this first after a restart)

- **Merged today:** #6 art-rights docs, #7 Xcode automatic signing (Product ▸ Archive works), #8 simpler
  home menu (Play / Journey / New here? / More), #10 mid-game level change (tap "vs Level" above the board).
- **Branch `feat/visual-upgrade`, PR #11 (open):** hero board image on Home; opponent badge/name/seeds
  strip above the board + "You" strip below; five board looks (`BoardTheme.swift`: Heritage, Evening free;
  Ebony, Cape Coast, Kente with the purchase) picked in Settings; lesson highlights the house to tap
  (pulsing gold ring) and shows step dots. Fixed a double-parent SKNode crash in `BoardScene.highlight`.
  XCUITests 10/10 green locally. **To do:** confirm the TypeScript suite + screenshots pass
  (`cd e2e && OWARE_SIM_NAME="iPhone 18 Pro Max" OWARE_SCREENSHOTS=1 npx wdio run wdio.conf.ts`),
  look at `e2e/screenshots/{home,board,tutorial}.png`, then merge PR #11 when CI is green.
- **Local gotchas learned today:** macOS has no `timeout` command; Appium hangs at session creation
  when several simulators are booted or a stale WebDriverAgent is left — shut extra sims down and
  reboot "iPhone 18 Pro Max". GitHub closes a PR whose base branch was deleted, so base PRs on main.
- **Owner's Apple ID situation:** developer.apple.com rejected Team ID 9MGS6Q2S9Q; the Xcode dev cert on
  this Mac is for rforjoe@live.co.uk / team 6YH7H8GC4R. He needs to sign in with the Apple ID that
  holds the paid membership and use that Team ID. The app runs on his iPhone from Xcode after trusting
  the developer certificate in Settings ▸ General ▸ VPN & Device Management.
- **Owner ideas from a mock-up he shared (not done, by design):** tab bar, coins, online matches,
  leaderboards, friends — online is v1.1; coins ruled out; he asked for a simple menu.

## Next steps (in order)

1. **Merge PR #5** when CI is green (I merge once green unless told otherwise).
2. **Milestone 5 — polish & ship v1** (new branch `feat/polish`):
   - Real drum audio to replace `SoundPlayer`'s synthesised buffers (owner to source/record CC0 atumpan,
     fontomfrom samples, or approve keeping the synthesised set for v1).
   - Adinkra vector icons for Undo (Sankofa) and Hint (Nyansapo) drawn cleanly; until then SF Symbols.
   - Cosmetic unlocks that the purchase promises (at least one alternative seed set and board tint).
   - App Store screenshots: iPhone 6.9" set is produced by `e2e/specs/screenshots.spec.ts` at 1320×2868;
     iPad 13" set from `screenshots-ipad13/` (2064×2752). Add captions in Canva if wanted.
   - Accessibility sweep with VoiceOver on device; Dynamic Type check for the Heritage text.
3. ~~Owner decision on art rights~~ — **decided 2026-09-24: keep the Canva-generated art** (see
   `docs/ART_DIRECTION.md` §3 for the terms, obligations and provenance record).
4. **Owner-gated release steps** (`docs/PIPELINE.md`): Apple secrets → `SIGNING_READY=true` → first
   TestFlight build on merge; create IAP product `com.richardforjoe.oware.fulljourney`; host the
   privacy policy and add the support email; fill App Store Connect from `docs/APP_STORE.md`.
5. **v1.1 — Online** via Game Center turn-based matches (GAME_PLAN §3.1), leaderboards, achievements.

## Useful commands

```bash
make project        # regenerate Oware.xcodeproj
make engine-test    # swift test for the rules engine
make test           # app unit + XCUITest on simulator
make e2e            # Maestro flows on simulator
make e2e-ts         # TypeScript Appium suite (cd e2e && npm install first)
gh pr checks 1 -R richardforjoejnr/oware --watch
```
