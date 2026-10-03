# Monorepo conventions

## One folder per app
`apps/<app-slug>/` is self-contained: `project.yml`, `<Name>/Sources` + `Resources`, `<Name>Tests`,
`<Name>UITests`, `e2e/` (Appium + WebdriverIO), `.maestro/`, `fastlane/`, `docs/`, `art/` and a
`Makefile`. Nothing in an app folder references another app. Shared code goes in `packages/`.

## Shared packages
`packages/<Package>/` are plain SwiftPM packages, referenced from an app's `project.yml` as
`path: ../../packages/<Package>`. They must build with `swift test` alone (no Xcode), which is what
the "Engine (swift test)" CI job runs.

## Shared kits
`packages/SupportKit` is the tip jar every app can adopt: `TipJar(productIDs:)` in the environment plus
`TipJarView(style:)`. Product ids follow `<bundle id>.tip.small|medium|large`.

## Bundle ids and names
`com.richardforjoe.<app-slug-without-dashes>`; display names live in each `project.yml`.
Fastlane's `Appfile` reads `APP_IDENTIFIER` from the environment with the app's id as default.

## CI per app
Each app has its own workflows, filtered by `paths:` so a change to one app never builds the other:
Lelu Oware has `ci.yml` and `e2e.yml` (its app, OwareEngine, SupportKit, scripts, its site pages);
Lelu Ludo has `ludo-ci.yml` (its app and LudoEngine). Pure-Swift packages are tested on Linux in the
`swift` container where they can be (a tenth of a macOS runner's cost on a private repository);
anything that needs the simulator runs on macOS. The website's infrastructure has `site-ci.yml`.
TestFlight / release workflows are copied per app the same way; secrets are shared across the
team's apps, `SIGNING_READY` gates them. (Branch protection is not available on a free private
repository, so path-filtered workflows cannot leave a required check waiting.)

## Scaffolding
`make new-app NAME=my-app DISPLAY="My App"` copies `templates/ios-app` into `apps/my-app`, renames
the targets, and generates the Xcode project. Then add the workflow copies and, if the app is
released, a fastlane `Matchfile` entry.

## Generated files
`*.xcodeproj` is never committed (see `.gitignore`); `make project` regenerates it. Derived data
lives in `apps/<app>/build/`.
