# Build & release pipeline

```
feature branch ──PR──▶ CI (engine tests + unsigned simulator build/test)
        │
      merge to main ──▶ TestFlight workflow, only when the merge changes the app
        │                 (signed Release build → TestFlight, build # = UTC date and time,
        │                  tagged build/<version>-<build #>)
        │
  run App Store Release from a build tag ──▶ that same build → App Review → live when approved;
                                             tags vX.Y.Z and publishes the GitHub Release
```

Workflows live in `.github/workflows/`; build logic lives in each app's `fastlane/Fastfile`
(`apps/lelu-oware/fastlane/Fastfile`, run with `BUNDLE_GEMFILE=../../Gemfile`) so the same
lanes run locally and in CI.

| Workflow | Trigger | Needs secrets? | Result |
|---|---|---|---|
| `ci.yml` | every PR, every push to `main` | No | Green tick on the PR; test results as artifacts |
| `e2e.yml` | every PR, every push to `main` | No | Maestro and Appium (TypeScript) UI flows on a simulator; JUnit reports as artifacts |
| `pr-title.yml` | PR opened / edited / updated | No | Fails unless the PR title is a Conventional Commit (it decides the version) |
| `testflight.yml` | push to `main` that changes the app (paths below), or manual | Yes | New build in TestFlight, tagged `build/<version>-<build #>` |
| `release.yml` | manual, from a `build/…` tag | Yes | That build submitted for App Review with "What's New", released automatically once approved; tags `vX.Y.Z` and publishes the GitHub Release |
| `pages.yml` ("Site") | docs or site change on `main`, a release, CI / E2E finishing on `main`, or manual | AWS keys | Website on AWS (S3 + CloudFront): privacy, support, What's new, test reports |

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

Which App Review guidelines are checked automatically, and which need checking by hand, is in
[APP_REVIEW.md](APP_REVIEW.md).

`python3 scripts/release_readiness.py apps/<app>` runs on every PR (CI job "App Store readiness") and
again before every App Store upload. It fails on the things that get uploads rejected or pulled: a
missing or incomplete privacy manifest (every required-reason API needs a declared reason), test
switches in release builds, an icon with transparency, unexpected entitlements, plain-http links, and
placeholder text or a missing contact email on the public privacy and support pages.

## Releasing to the App Store

Every TestFlight upload is tagged `build/<version>-<build number>` (e.g. `build/1.0.1-202610021230`)
on the commit it was built from. To ship one: Actions ▸ **App Store Release** ▸ **Run workflow** ▸
**Use workflow from** ▸ **Tags** ▸ pick the build ▸ **Run workflow**. It:

1. submits that exact build (nothing is rebuilt) for App Review, with "What's New" made from the
   `feat:` / `fix:` / `perf:` PR titles since the last release (`next_version.py --store-notes`;
   left out for the very first version, which has no "What's New"),
2. lets Apple release it to everyone as soon as it is approved (no phased rollout),
3. tags `vX.Y.Z`, publishes the GitHub Release "Lelu Oware X.Y.Z" and refreshes the What's new page.

The App Store text, screenshots, privacy answers and age rating stay as set in App Store Connect.
The `production` environment can require your approval before it runs.

- **One version in review at a time.** Wait for Apple's answer before running it again.
- **Rejected?** Merge the fix; its TestFlight build is tagged with the next version (the rejected
  one already has its `v` tag). Run the workflow on that tag: App Store Connect's version number is
  updated to match. Delete the GitHub Release of the rejected version if you want a tidy history.
- **Released a version by hand** in App Store Connect? Publish a GitHub Release tagged `vX.Y.Z`,
  named "Lelu Oware X.Y.Z", on the commit of that build, so later builds move on to the next version.
  (Publishing a release by hand uploads nothing.)

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
- **Per app:** each app's version and notes count only the PRs that changed its own files (its
  folder and the packages it uses; `APP_PATHS` in `scripts/next_version.py`, chosen from the folder
  the workflow runs it in, or `--app=<slug>`). A Lelu Ludo feature never bumps Lelu Oware's version or
  appears in its "What's New". `vX.Y.Z` tags are Lelu Oware's releases; Lelu Ludo will get its own
  tag prefix when it reaches the App Store (its stage 5).
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
- **App Store** (App Store Release, run from a `build/X.Y.Z-N` tag): submits that build, then tags
  `vX.Y.Z`, publishes a GitHub Release named "Lelu Oware X.Y.Z" with the notes, and starts the Pages
  workflow (a release created by a workflow fires no `release` event). The next TestFlight builds then
  move on to the version after. Settings shows no "Beta" in App Store builds. (A GitHub Release
  published by hand must be named exactly "Lelu Oware X.Y.Z": the What's new page,
  `scripts/build_release_notes.py`, only lists releases named that way.)
- **Build number** (`CFBundleVersion`): the UTC date and time of the upload, e.g. 202609271730, for
  every upload (TestFlight and `make archive`), so builds never clash.
- Apple only accepts plain numbers as versions ("1.3.0", never "1.3.0-beta"); TestFlight itself marks
  builds as beta. The version open in App Store Connect must match (e.g. 1.0.0 for the first release).

Without CI secrets, upload from your Mac: `make archive APP=lelu-oware` (same version and build scheme),
then in the Organizer that opens: **Distribute App ▸ App Store Connect ▸ Upload**.

## Day-to-day flow
0. Once per clone: `make hooks`. Xcode projects then regenerate by themselves after every branch switch
   and pull (no more "cannot find type" errors from a stale project). `make project` fills in the
   Apple Team ID itself.
1. `git checkout -b feature/thing` → edit → `make engine-test` / `make test`.
2. Push, open a PR. CI must be green.
3. Merge → if the PR changed the app, a TestFlight build appears in ~15 minutes, tagged
   `build/<version>-<build #>` → test on your phone.
4. When a build is good: Actions ▸ App Store Release ▸ Run workflow from its tag (see "Releasing to
   the App Store"). Apple reviews it and it goes live when approved.

## Hosted pages (AWS)
Full setup, costs, troubleshooting and how to add another app: [WEBSITE_ON_AWS.md](WEBSITE_ON_AWS.md)
(local script: `scripts/setup-site.sh`).

The public website lives on AWS, not GitHub Pages, so the code repository can be private. The CDK
app in `infra/site` (same conventions as `aws-cdk-boilerplate`) keeps it in a private S3 bucket behind
CloudFront (Origin Access Control, HTTPS only, security headers, a 404 page); `infra/site/test` checks
those properties and the short-URL function. `.github/workflows/pages.yml` ("Site") builds `docs/`
with Jekyll, adds `/<app>/whats-new` from the GitHub Releases and a **test report** per app at
`/reports/<app>/` (from the latest successful main-branch CI and E2E runs, via
`scripts/build-reports.py`), writes each page as `<page>/index.html` too (`scripts/site_pretty_urls.py`)
so `/lelu-oware/privacy` works, then runs `infra/site/scripts/deploy.sh prod`. It runs when docs or
the site change, when a release is published (or the App Store workflow starts it), and after CI / E2E
complete for a push to main. The run summary lists the URLs to paste into App Store Connect.

Setup (once): repository secrets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (the `cdk-deployer`
IAM user, as in aws-cdk-boilerplate), and repository variable `SITE_ON_AWS` = `true`. After buying a
domain in Route 53, set the variable `SITE_DOMAIN` (e.g. `leluoware.com`): the next deploy adds its
certificate and DNS records, and the site answers on the domain and on `www`. To deploy from a Mac:
build the site, then `SITE_DIR=$PWD/_site infra/site/scripts/deploy.sh prod`.

Lelu Oware: https://leluoware.com/lelu-oware/privacy and …/support (domain `leluoware.com`,
bought in Route 53 in account 842822459513; CloudFront also answers at
https://diqw2b8iw2b16.cloudfront.net). Support email: trendnestorg34@gmail.com.

## Before the first App Store submission (checklist)
- [ ] App Store Connect: privacy policy URL, support URL, age rating questionnaire (4+), category **Games › Board**
- [ ] App Privacy: see `apps/lelu-oware/docs/SERVICES.md` section 5 (analytics change the answer)
- [ ] Screenshots for 6.9" iPhone and 13" iPad (generated from the real app)
- [ ] App icon 1024×1024 in `Oware/Resources/Assets.xcassets/AppIcon.appiconset`
- [ ] Export compliance already answered in Info.plist (`ITSAppUsesNonExemptEncryption = false`)
