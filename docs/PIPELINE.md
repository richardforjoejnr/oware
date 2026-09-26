# Build & release pipeline

```
feature branch ──PR──▶ CI (engine tests + unsigned simulator build/test)
        │
      merge to main ──▶ TestFlight workflow (signed Release build → TestFlight, build # = run number)
        │
  publish GitHub Release vX.Y.Z ──▶ App Store workflow (signed build → App Store Connect,
                                     optional "submit for review", manual approval gate)
```

Workflows live in `.github/workflows/`; build logic lives in each app's `fastlane/Fastfile`
(`apps/lelu-oware/fastlane/Fastfile`, run with `BUNDLE_GEMFILE=../../Gemfile`) so the same
lanes run locally and in CI.

| Workflow | Trigger | Needs secrets? | Result |
|---|---|---|---|
| `ci.yml` | every PR, every push to `main` | No | Green tick on the PR |
| `testflight.yml` | push to `main` (after merge), or manual | Yes | New build in TestFlight |
| `release.yml` | GitHub Release published (tag `v1.0.0`), or manual | Yes | Build in App Store Connect; submit for review if chosen |

The signed workflows are skipped until the repository variable `SIGNING_READY` is `true`, so
merging is safe before Apple credentials are configured.

---

## What you need to provide (one-time)

### A. Apple side
1. **Apple Developer Program membership** (US$99/year) — https://developer.apple.com/programs/enroll/
   Enrol as an individual (your name shows as the seller) or as an organisation (needs a D-U-N-S number).
2. **App record in App Store Connect** — https://appstoreconnect.apple.com → My Apps → "+" → New App
   - Platform iOS, name (e.g. "Oware: Seeds of Ghana"), primary language English (UK),
     Bundle ID `com.richardforjoe.oware` (register it first under Certificates, IDs & Profiles → Identifiers,
     enable **Game Center** and **In-App Purchase** capabilities), SKU `oware-ios`.
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
6. **In-app purchase** — App Store Connect → your app → Monetization → In-App Purchases → "+":
   Non-Consumable, Reference name "Full Journey", Product ID `com.richardforjoe.oware.fulljourney`,
   price tier ≈ £3.99, display name "The Full Journey", description from `docs/APP_STORE.md`.
   Submit it with the first build that uses it (Apple reviews IAPs alongside the binary).
7. **TestFlight testers** — App Store Connect → TestFlight → Internal Testing → add yourself.
   Install the TestFlight app on your iPhone.

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

1. `export DEVELOPMENT_TEAM=<your 10-character Team ID>` (add it to `~/.zshrc`), then `make open`.
2. In Xcode choose the **Oware** scheme and destination **Any iOS Device (arm64)**.
3. Product ▸ Archive. When the Organizer opens: **Distribute App ▸ TestFlight & App Store ▸ Upload**,
   accept the defaults (automatic signing creates the certificate and profile for you).
4. In App Store Connect ▸ your app ▸ TestFlight the build appears after processing (5–15 min).
   Under Internal Testing add a group with yourself; open the TestFlight app on your iPhone and install.
   Prerequisites: the App ID and app record from section A steps 1–2 must exist first.

## Day-to-day flow
1. `git checkout -b feature/thing` → edit → `make engine-test` / `make test`.
2. Push, open a PR. CI must be green.
3. Merge → a TestFlight build appears in ~15 minutes → test on your phone.
4. When ready to ship: Releases → "Draft a new release" → tag `v1.0.0` → Publish.
   The App Store workflow uploads the build; approve the `production` environment; then in App Store
   Connect attach the build to the version, fill metadata/screenshots, and submit (or set
   `submit_for_review` on a manual run).

## Before the first App Store submission (checklist)
- [ ] App Store Connect: privacy policy URL, support URL, age rating questionnaire (4+), category **Games › Board**
- [ ] App Privacy: "Data Not Collected" (true as long as we add no analytics/ads)
- [ ] Screenshots for 6.9" iPhone and 13" iPad (generated from the real app)
- [ ] App icon 1024×1024 in `Oware/Resources/Assets.xcassets/AppIcon.appiconset`
- [ ] In-app purchases created in App Store Connect and reviewed with the same build
- [ ] Game Center leaderboards/achievements configured
- [ ] Export compliance already answered in Info.plist (`ITSAppUsesNonExemptEncryption = false`)
