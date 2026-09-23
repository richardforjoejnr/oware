# Oware — Ghana's game, for iPhone and iPad

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

## Contributing flow
Branch → PR (CI runs) → merge to `main` (TestFlight build) → GitHub Release `vX.Y.Z` (App Store).
