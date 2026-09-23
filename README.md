# Lelu Oware — Ghana's game, for iPhone and iPad

A native iOS Oware (Abapa rules) game with authentic Ghanaian art direction.
Plan and design: **[docs/GAME_PLAN.md](docs/GAME_PLAN.md)**. Build/release pipeline: **[docs/PIPELINE.md](docs/PIPELINE.md)**.

## Layout
```
project.yml            XcodeGen spec (source of truth; Oware.xcodeproj is generated, not committed)
Oware/                 SwiftUI app target
OwareTests/            App unit tests
Packages/OwareEngine/  Pure-Swift rules engine + tests (runs with `swift test`, no Xcode needed)
fastlane/              Build/sign/upload lanes used by CI
.github/workflows/     CI, TestFlight, App Store release
docs/                  Plan, pipeline, cultural sources
```

## Getting started
```bash
./scripts/bootstrap.sh     # installs xcodegen etc. and generates Oware.xcodeproj
make open                  # open in Xcode
make engine-test           # rules-engine tests (Command Line Tools are enough)
make test                  # full app tests on a simulator
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
