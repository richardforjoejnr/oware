# richardforjoe iOS apps — monorepo

Native iOS apps, one per folder under `apps/`, sharing Swift packages under `packages/` and one
set of tooling, CI and release lanes.

| App | Folder | Notes |
|---|---|---|
| **Lelu Oware** | [`apps/lelu-oware`](apps/lelu-oware/README.md) | Ghana's game of Oware, Abapa rules. Ships first. |

## Layout
```
apps/<app>/            One iOS app: project.yml (XcodeGen), Sources, tests, e2e, fastlane, docs, art
packages/<Package>/    Shared Swift packages (OwareEngine: rules + AI; SupportKit: tip jar)
templates/ios-app/     Starting point for a new app (make new-app NAME=…)
scripts/               Shared helpers (simulator picker, bootstrap, scaffolding)
.github/workflows/     CI / E2E / TestFlight / App Store per app
docs/                  Repo-wide docs: PIPELINE.md (credentials + release), MONOREPO.md (conventions)
Gemfile                fastlane for every app (BUNDLE_GEMFILE points here)
```

## Everyday commands (run from the repo root)
```bash
./scripts/bootstrap.sh          # tools + generate every app's .xcodeproj
make open                       # Xcode for the default app (APP=lelu-oware)
make test                       # unit + UI tests on a simulator
make engine-test                # shared package tests
make new-app NAME=my-app DISPLAY="My App"   # scaffold a second app
```
Each app also has its own Makefile, so `cd apps/lelu-oware && make test` works too.
`*.xcodeproj` files are generated, never committed: after pulling, run `make project`.

## Adding an app
See [docs/MONOREPO.md](docs/MONOREPO.md): scaffold, bundle id, a copy of `ci.yml` with its own job
names, and branch-protection checks.
