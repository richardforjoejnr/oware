# Build & release pipeline

```
feature branch ──PR──▶ CI (engine tests + unsigned simulator build/test)
        │
      merge to main ──▶ TestFlight workflow, only when the merge changes the app
        │                 (signed Release build → TestFlight, build # = UTC date and time)
        │
  publish GitHub Release vX.Y.Z ──▶ App Store workflow (signed build → App Store Connect,
                                     optional "submit for review", manual approval gate)
```

Workflows live in `.github/workflows/`; build logic lives in each app's `fastlane/Fastfile`
(`apps/lelu-oware/fastlane/Fastfile`, run with `BUNDLE_GEMFILE=../../Gemfile`) so the same
lanes run locally and in CI.

| Workflow | Trigger | Needs secrets? | Result |
|---|---|---|---|
| `ci.yml` | every PR, every push to `main` | No | Green tick on the PR; test results as artifacts |
| `e2e.yml` | every PR, every push to `main` | No | Maestro and Appium (TypeScript) UI flows on a simulator; JUnit reports as artifacts |
| `pr-title.yml` | PR opened / edited / updated | No | Fails unless the PR title is a Conventional Commit (it decides the version) |
| `testflight.yml` | push to `main` that changes the app (paths below), or manual | Yes | New build in TestFlight |
| `release.yml` | GitHub Release published (tag `v1.0.0`), or manual from `main` | Yes | Build in App Store Connect; submit for review if chosen; a manual run tags `vX.Y.Z` and publishes the GitHub Release |
| `pages.yml` | docs change on `main`, a release, CI / E2E finishing on `main`, or manual | No | GitHub Pages: docs site, What's new page, test reports |

The signed workflows are skipped until the repository variable `SIGNING_READY` is `true`, so
merging is safe before Apple credentials are configured.

---

## What you need to provide (one-time)

### A. Apple side
1. **Apple Developer Program membership** (US$99/year) — https://developer.apple.com/programs/enroll/
   Enrol as an individual (your name shows as the seller) or as an organisation (needs a D-U-N-S number).
2. **App record in App Store Connect** — https://appstoreconnect.apple.com → My Apps → "+" → New App
   - Platform iOS, name **Lelu Oware**, primary language English (UK),
     Bundle ID `com.richardforjoe.oware` (register it first under Certificates, IDs & Profiles → Identifiers,
     enable **In-App Purchase** and **Game Center**), SKU `oware-ios`. Name: **Lelu Oware**.
3. **App Store Connect API key** — Users and Access → Integrations → App Store Connect API → "+"
   - Name: `github-actions`, Access: **App Manager**. Download the `.p8` **once** (it can't be re-downloaded).
   - Note the **Key ID** and **Issuer ID**.
4. **Code-signing storage (fastlane match)** — create a **private** empty GitHub repo, e.g.
   `richardforjoejnr/oware-certificates`, and a GitHub **fine-grained personal access token** with
   *Contents: read/write* on that repo only.
5. **Generate certificates once from your Mac** (after Xcode is installed and `bundle install` done):
   ```bash
   export MATCH_GIT_URL=https://github.com/richardforjoejnr/oware-certificates
   export MATCH_PASSWORD='choose-a-strong-passphrase'
   export DEVELOPMENT_TEAM=XXXXXXXXXX          # Team ID from developer.apple.com/account
   export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_CONTENT="$(base64 -i AuthKey_XXXX.p8)"
   bundle exec fastlane match appstore --readonly false
   bundle exec fastlane match development --readonly false   # for running on your own iPhone
   ```
6. **Tip jar products** — App Store Connect → your app → Monetization → In-App Purchases → "+":
   three **Consumable** products exactly as listed in `apps/lelu-oware/docs/APP_STORE.md` (tip.small /
   tip.medium / tip.large). They unlock nothing; submit them with the first build (Apple reviews IAPs
   alongside the binary). Add the review note from that doc.
7. **TestFlight testers** — App Store Connect → TestFlight → Internal Testing → add yourself.
   Install the TestFlight app on your iPhone.

### Shortcut: one script for steps A3–A5 and B

After creating the API key (A3) and a fine-grained token (A4), run `./scripts/setup-signing.sh` in
Terminal from the repo root. It asks for each value privately, creates the private certificates
repo if needed, runs `fastlane match` once (`fastlane ios setup_signing`), adds every secret below to
GitHub, and turns `SIGNING_READY` on last. Name the API key `github-actions`, access **App Manager**.
Apple only lets **Admin** keys create a distribution certificate, so also create a second key
(`match-setup`, access Admin) and give it at the script's "Admin Key ID" prompt. It is used once and
not stored; revoke it afterwards. Done for Lelu Oware on 27 September 2026.

### B. GitHub side (Settings → Secrets and variables → Actions)

Secrets:

| Secret | Value |
|---|---|
| `DEVELOPMENT_TEAM` | 10-character Apple Team ID |
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID |
| `ASC_KEY_CONTENT` | `base64 -i AuthKey_XXXX.p8` output (single line) |
| `MATCH_GIT_URL` | `https://github.com/richardforjoejnr/oware-certificates` |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `echo -n "richardforjoejnr:<fine-grained-PAT>" \| base64` |
| `MATCH_PASSWORD` | the passphrase you chose in step A5 |

Variables:

| Variable | Value |
|---|---|
| `SIGNING_READY` | `true` (flip this on once the secrets above exist) |

Environments (Settings → Environments): create `testflight` and `production`. On `production`,
add yourself as a **required reviewer** so an App Store upload always waits for your click.

Branch protection on `main` is configured to require the CI check and a pull request.

### C. Your Mac
- **Xcode** (App Store, id 497799835) then `sudo xcode-select -s /Applications/Xcode.app` and open it once to accept the licence.
- `./scripts/bootstrap.sh` (installs xcodegen, xcbeautify, swiftlint; generates every app's project).
- Ruby 3.x for fastlane locally (optional; CI has it): `brew install ruby` then `bundle install`.
- Sign in to Xcode with your Apple ID (Settings → Accounts) to run on your own iPhone.

---

## Fastest way to a TestFlight build (no CI secrets needed)

1. `export DEVELOPMENT_TEAM=<your 10-character Team ID>` (add it to `~/.zshrc`).
2. `make archive APP=lelu-oware`. It builds a Release archive with a fresh build number (see
   "Versions and build numbers" below) and opens it in Xcode's Organizer. (Product ▸ Archive in
   Xcode also works, but it reuses build 1, so a second upload is rejected.)
3. In the Organizer: **Distribute App ▸ App Store Connect ▸ Upload**, accepting the defaults
   (automatic signing creates the certificate and profile for you).
4. In App Store Connect ▸ your app ▸ TestFlight the build appears after processing (5–15 min).
   Under Internal Testing add a group with yourself; open the TestFlight app on your iPhone and install.
   Prerequisites: the App ID and app record from section A steps 1–2 must exist first.

## App Store readiness checks

`python3 scripts/release_readiness.py apps/<app>` runs on every PR (CI job "App Store readiness") and
again before every App Store upload. It fails on the things that get uploads rejected or pulled: a
missing or incomplete privacy manifest (every required-reason API needs a declared reason), test
switches in release builds, an icon with transparency, unexpected entitlements, plain-http links, and
placeholder text or a missing contact email on the public privacy and support pages.

## Deploying to the App Store by hand

Actions ▸ **App Store Release** ▸ **Run workflow**: leave the version empty (the next version from
PR titles) or type one, and tick **submit for review** if the text, screenshots, privacy answers and
age rating are already filled in App Store Connect. After uploading it tags the release. Publishing a
GitHub Release tagged `vX.Y.Z` does the same with that version. The `production` environment can require your approval before it runs.

## Versions and build numbers

Automatic, from **Conventional Commit PR titles** (checked on every PR by the "PR title" workflow):

| PR title starts with | Next version after 1.2.3 |
|---|---|
| `feat!:` (any type with `!`) | 2.0.0 |
| `feat:` | 1.3.0 |
| `fix:`, `perf:`, `refactor:`, `build:`, `revert:` | 1.2.4 |
| `docs:`, `chore:`, `ci:`, `test:`, `style:` only | no new version, not in the release notes |

- **Breaking changes need `!` in the PR title.** PRs are merged with a merge commit whose message is
  the PR title (repository setting: merge commit message = "Pull request title"; a squash merge also
  uses the title), so a `BREAKING CHANGE:` note in the PR description never reaches git. (A
  `BREAKING CHANGE` / `BREAKING-CHANGE` note in a commit body is still honoured if one gets there.)
- **Release** = a git tag `vX.Y.Z`. `scripts/next_version.py` reads the PR titles merged since the last
  tag and prints the next version (1.0.0 before the first release); `--notes` prints release notes.
- **Titles from before the convention** (PRs up to #35) are read leniently: `Docs: …` counts as
  docs, `Fix: …` as a fix, and any other title (`Accessibility: …`, `Milestone 2: …`) is a player-facing
  change listed in full under "Also". The first release's notes therefore list the whole history;
  shorten them in the GitHub Release (and TestFlight's "What to Test") if you want a tidier page.
  Alternatively, before the first release, tag a baseline on the commit to start counting from
  (`git tag v0.9.0 <sha> && git push origin v0.9.0`): later notes then only list PRs after it, but
  the next version is computed from that tag (TestFlight betas become 0.9.x / 0.10.0 until the first
  release), so give the first App Store run an explicit version such as 1.0.0.
- **TestFlight** runs on a merge to `main` that touches `apps/lelu-oware/Oware/**` (app code and
  resources), `apps/lelu-oware/project.yml`, `apps/lelu-oware/fastlane/**`, `packages/*/Sources/**`,
  `packages/*/Package.swift`, the `Gemfile` or `testflight.yml` itself; not docs, the website, other
  CI files, scripts or tests. The build gets the *next* version, and its "What to Test"
  notes list the player-facing PRs since the last release. A beta always moves past the released
  version, even if only a `chore:` touched the app. A manual run with nothing merged since the last
  tag skips the upload (there is no new version to build). In the app, Settings shows "Version 1.3.0 (build) · Beta".
- **App Store** (Actions ▸ App Store Release ▸ Run workflow, version left empty): builds that same next
  version, uploads it, then tags `vX.Y.Z`, publishes a GitHub Release named "Lelu Oware X.Y.Z" with
  the notes, and starts the Pages workflow (a release created by a workflow fires no `release` event). The next
  TestFlight builds then move on to the version after. Settings shows no "Beta" in App Store builds.
  (Publishing a GitHub Release tagged `vX.Y.Z` by hand works too. Name it exactly "Lelu Oware X.Y.Z":
  the What's new page, `scripts/build_release_notes.py`, only lists releases named that way.)
- **Build number** (`CFBundleVersion`): the UTC date and time of the upload, e.g. 202609271730, for
  every upload (TestFlight, App Store, `make archive`), so builds never clash.
- Apple only accepts plain numbers as versions ("1.3.0", never "1.3.0-beta"); TestFlight itself marks
  builds as beta. The version open in App Store Connect must match (e.g. 1.0.0 for the first release).

Without CI secrets, upload from your Mac: `make archive APP=lelu-oware` (same version and build scheme),
then in the Organizer that opens: **Distribute App ▸ App Store Connect ▸ Upload**.

## Day-to-day flow
1. `git checkout -b feature/thing` → edit → `make engine-test` / `make test`.
2. Push, open a PR. CI must be green.
3. Merge → if the PR changed the app, a TestFlight build appears in ~15 minutes → test on your phone.
4. When ready to ship: Actions ▸ App Store Release ▸ Run workflow on `main` (see above), or
   Releases → "Draft a new release" → tag `v1.0.0`, title "Lelu Oware 1.0.0" → Publish.
   The App Store workflow uploads the build; approve the `production` environment; then in App Store
   Connect attach the build to the version, fill metadata/screenshots, and submit (or set
   `submit_for_review` on a manual run).

## Hosted pages
GitHub Pages is deployed by `.github/workflows/pages.yml` (Settings ▸ Pages ▸ Source: **GitHub Actions**).
It builds `docs/` with Jekyll (index, per-app privacy and support pages) and adds a **test report** per
app at `/reports/<app>/`, generated by `scripts/build-reports.py` from the latest successful main-branch
CI and E2E push runs' artifacts (xcresult summary JSON, Appium and Maestro JUnit XML, screenshots).
It also writes `/<app>/whats-new` from the GitHub Releases. It runs when docs change, when a release
is published (or the App Store workflow starts it), and after CI / E2E complete for a push to main
(fork PRs whose branch is named main are ignored). Deployments queue rather than cancel each other. Lelu Oware: https://richardforjoejnr.github.io/oware/lelu-oware/privacy and
…/support, and the newsletter page …/newsletter. Support email: trendnestorg34@gmail.com.

## Before the first App Store submission (checklist)
- [ ] App Store Connect: privacy policy URL, support URL, age rating questionnaire (4+), category **Games › Board**
- [ ] App Privacy: see `apps/lelu-oware/docs/SERVICES.md` section 5 (analytics change the answer)
- [ ] Screenshots for 6.9" iPhone and 13" iPad (generated from the real app)
- [ ] App icon 1024×1024 in `Oware/Resources/Assets.xcassets/AppIcon.appiconset`
- [ ] Export compliance already answered in Info.plist (`ITSAppUsesNonExemptEncryption = false`)
