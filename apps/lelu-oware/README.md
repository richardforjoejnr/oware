# Lelu Oware — Ghana's game, for iPhone and iPad

A native iOS Oware (Abapa rules) game with authentic Ghanaian art direction.
Part of the richardforjoe iOS monorepo (see the [root README](../../README.md)).
Plan and design: **[docs/GAME_PLAN.md](docs/GAME_PLAN.md)**. Build/release pipeline: **[../../docs/PIPELINE.md](../../docs/PIPELINE.md)**.

## Layout
```
project.yml                  XcodeGen spec (source of truth; Oware.xcodeproj is generated, not committed)
Oware/                       SwiftUI app target
OwareTests/  OwareUITests/   App unit tests, XCUITests
e2e/  .maestro/              Appium + WebdriverIO (TypeScript) and Maestro flows
../../packages/OwareEngine/  Pure-Swift rules engine + AI (runs with `swift test`, no Xcode needed)
fastlane/                    Build/sign/upload lanes used by CI
../../.github/workflows/     CI, TestFlight, App Store release
docs/                        Plan, status hand-off, art direction, cultural sources, store listing
```

## Getting started
```bash
../../scripts/bootstrap.sh   # from the repo root: installs xcodegen etc. and generates the projects
make open                    # open in Xcode (or `make open` at the repo root)
make test                    # full app tests on a simulator
(cd ../.. && make engine-test)   # rules-engine tests (Command Line Tools are enough)
```

## Building on your own iPhone without the paid developer programme
A free Apple ID is enough for the simulator and for running on your own device (7-day install,
no Game Center / IAP). In Xcode → Settings → Accounts, sign in; note the Personal Team ID shown
there. Because `Oware.xcodeproj` is regenerated, set the team before generating so it sticks:
```bash
export DEVELOPMENT_TEAM=YOURTEAMID   # add to ~/.zshrc to make it permanent
make open
```
Then select the Oware target → Signing & Capabilities → your Personal Team, and Run on your phone.
TestFlight, App Store, In-App Purchase and Game Center need the paid programme (see docs/PIPELINE.md).

## Contributing flow
Branch → PR (CI runs) → merge to `main` (TestFlight build) → GitHub Release `vX.Y.Z` (App Store).
