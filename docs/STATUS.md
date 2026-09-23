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
| Local Mac | XcodeGen, xcbeautify, mas installed. Maestro CLI at `~/.maestro/bin` (PATH added in `~/.zshrc`) but **needs Java**. Node 22 + npm present; `e2e/node_modules` installed. **Xcode 27 installed but licence not accepted.** |

## In progress (as of last session)

- Latest push made the Appium/TS CI job use `npm install` instead of `npm ci` (lock file could not
  reconcile sharp's optional platform binaries). Verify the "Appium + WebdriverIO (TypeScript)"
  check is green on PR #1; if not, read the job log with
  `gh api repos/richardforjoejnr/oware/actions/jobs/<job-id>/logs`.
- Consider adding "Appium + WebdriverIO (TypeScript)" to the required checks on `main` once stable.

## Blocked on the owner (needs a password or Apple account)

1. Accept the Xcode licence (this also unblocks `git`, `python3`, `xcodebuild` on the Mac):
   `sudo xcodebuild -license accept`
   Until then use `/Library/Developer/CommandLineTools/usr/bin/git` and `/opt/homebrew/bin/python3.11`.
2. Java for Maestro: `brew install --cask temurin`
3. Apple credentials → GitHub secrets, exactly as listed in `docs/PIPELINE.md` §A–B, then set
   repo variable `SIGNING_READY=true`.
4. Merge PR #1.
5. Confirm the meaning/origin of "Lelu" for the Heritage text and store description.
6. Say "plan approved" (or request changes) so Milestone 1 can begin.

## Next steps (in order)

1. **Milestone 0 — art direction.** Generate concept art with the connected Adobe/Canva tools:
   board (carved osese wood, stool base), nickernut seeds, Adinkra icon set (Sankofa, Nyansapo,
   Adinkrahene, Dwennimmen, Eban, Nkyinkyim, Mate Masie, Aya, Akoma, Funtunfunefu-Denkyemfunefu),
   Kente border patterns, Journey backdrops (Kumasi, Bonwire, Bosomtwe, Techiman, Cape Coast,
   Accra, Volta, Mole), app icon. Licence-check generated imagery; write `docs/STYLE_GUIDE.md`.
2. **Milestone 1 — rules engine** in `Packages/OwareEngine`: `RuleSet`, `Move`, `apply(move)`
   emitting events (sow, skipOrigin, capture, grandSlamForfeit, mustFeed, gameOver), `legalMoves()`,
   cycle detection, notation + replay. Exhaustive tests for every rule row in GAME_PLAN §2.1.
   CLI self-play to sanity-check seed conservation (always 48).
3. **Milestone 2 — playable core**: SpriteKit board scene in `SpriteView`, per-seed sowing animation,
   haptics, long-press landing preview, Pass & Play, AI levels 1–4 (`Packages/OwareAI`), save/resume.
   Add accessibility ids `house-A1…A6`, `house-B1…B6`, `store-A`, `store-B`, `btn-undo`, etc.
   First TestFlight build.
4. Milestones 3–5 per GAME_PLAN §6 (Learn & Puzzles → Journey → Polish & ship v1). Online in v1.1.

## Useful commands

```bash
make project        # regenerate Oware.xcodeproj
make engine-test    # swift test for the rules engine
make test           # app unit + XCUITest on simulator
make e2e            # Maestro flows on simulator
make e2e-ts         # TypeScript Appium suite (cd e2e && npm install first)
gh pr checks 1 -R richardforjoejnr/oware --watch
```
