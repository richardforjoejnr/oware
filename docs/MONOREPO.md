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
Shared templates + thin callers. The real steps live in two reusable workflows (`on: workflow_call`,
no triggers of their own):

- `reusable-swift-package.yml`: `swift test` for one package. Inputs `package-path`, `runner`
  (`linux`: the `swift:6.0` container on ubuntu, a tenth of a macOS runner's cost on a private
  repository, for pure-Swift packages; `macos`: macos-15 + latest stable Xcode, for packages that
  import Apple frameworks) and `parallel`.
- `reusable-ios-app.yml`: XcodeGen, package resolution (retried), simulator build + test, and the
  test results uploaded as an artifact. Inputs `app-dir`, `project`, `scheme`, `artifact-name`.

Each app has its own thin caller, filtered by `paths:` to that app's files plus the templates it
calls:

| Change | Runs |
| --- | --- |
| `apps/lelu-oware/**`, `packages/OwareEngine/**`, `packages/SupportKit/**`, `docs/lelu-oware/**` | Lelu Oware: `ci.yml` ("CI") and `e2e.yml` ("E2E (Maestro)") |
| The scripts Oware's jobs use (`release_readiness.py`, `next_version.py`, `build_release_notes.py`, `site_pretty_urls.py`, their tests, `pick-simulator.sh`), `Gemfile*`, `ci.yml` | Lelu Oware `ci.yml` (`pick-simulator.sh` also runs `e2e.yml`; editing `e2e.yml` runs only `e2e.yml`) |
| `apps/lelu-ludo/**`, `packages/LudoEngine/**`, `ludo-ci.yml` | Lelu Ludo: `ludo-ci.yml` only |
| `reusable-swift-package.yml` | every app that calls it (Oware CI and Ludo CI): it affects both |
| `reusable-ios-app.yml` | every app that calls it (Oware CI today; Ludo once it adds its app job) |
| Other scripts (e.g. `scripts/new-app.sh`), other docs | no app CI |

Lelu Oware's `ci.yml` keeps its name "CI" and its `TestResults` artifact: the Site workflow
(`pages.yml`) triggers on it and `scripts/build-reports.py` reads it (an artifact uploaded inside a
reusable workflow belongs to the caller's run). It also keeps its own App Store readiness job.
`e2e.yml` (Maestro + Appium) is Oware-only and does not use the templates. The website's
infrastructure has `site-ci.yml`. TestFlight / release workflows are copied per app (Oware's `testflight.yml` watches only OwareEngine and SupportKit, not every package); secrets are
shared across the team's apps, `SIGNING_READY` gates them. (Branch protection is not available on
a free private repository, so path-filtered workflows cannot leave a required check waiting.)

A new app adds `.github/workflows/<app>-ci.yml`:

```yaml
name: My App CI
on:
  pull_request:
    paths: [apps/my-app/**, packages/MyEngine/**, .github/workflows/my-app-ci.yml,
            .github/workflows/reusable-swift-package.yml, .github/workflows/reusable-ios-app.yml]
  push:
    branches: [main]
    paths: [apps/my-app/**, packages/MyEngine/**, .github/workflows/my-app-ci.yml,
            .github/workflows/reusable-swift-package.yml, .github/workflows/reusable-ios-app.yml]
permissions:
  contents: read
jobs:
  engine:
    name: MyEngine
    uses: ./.github/workflows/reusable-swift-package.yml
    with: { package-path: packages/MyEngine, runner: linux }
  app:
    name: iOS app
    uses: ./.github/workflows/reusable-ios-app.yml
    with: { app-dir: apps/my-app, project: MyApp.xcodeproj, scheme: MyApp, artifact-name: MyAppTestResults }
```

## Scaffolding
`make new-app NAME=my-app DISPLAY="My App"` copies `templates/ios-app` into `apps/my-app`, renames
the targets, and generates the Xcode project. Then add the workflow copies and, if the app is
released, a fastlane `Matchfile` entry.

## Generated files
`*.xcodeproj` is never committed (see `.gitignore`); `make project` regenerates it. Derived data
lives in `apps/<app>/build/`.
