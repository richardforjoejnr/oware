# App Review: what is checked automatically, and what is not

Apple's three sources, reviewed against Lelu Oware on 3 October 2026:
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines) and
[App Review](https://developer.apple.com/distribute/app-review/) (over 40% of rejections are
guideline 2.1: crashes, placeholder content, incomplete information).

## Checked on every PR and before every release

`scripts/release_readiness.py` (CI job "App Store readiness", and the first step of App Store Release):

| Guideline | Check |
|---|---|
| 5.1.1 privacy manifest | Manifest present, no tracking, a reason for every required-reason API, tip purchases declared |
| 5.1.1(i) privacy policy | Linked inside the app (Settings), names TelemetryDeck and Game Center, says how long data is kept, how to have it deleted and how to withdraw consent; public pages have no placeholders and show a contact email |
| 5.1.1(ii) consent | Usage stats default to off (the player is asked once, after a finished game) |
| 2.1 completeness | No placeholder text on screen; a linked newsletter page has a live form; test switches compiled out of release builds; no plain-http links |
| 2.3.1(a) hidden features | Feature flags are compile-time constants, so nothing can be switched on without a new review |
| 2.5 / export | Export compliance answered; permission prompts described; only expected entitlements |
| HIG ratings | No button calls `requestReview` (it may show nothing); the Rate button opens the write-review page |
| HIG launching / icons | A launch screen is configured; the 1024 pt icon has no transparency |

Tests:

| Guideline | Test |
|---|---|
| 2.1 crashes | Unit, UI and E2E suites; engine fuzz tests (whole games under every rule set) |
| HIG accessibility | `AccessibilityAuditUITests`: Apple's audit (hit regions, labels, traits…) on Home, Game, Settings, the tip jar, Riddles, Journey and Rules. `ThemeContrastTests`: text colours meet WCAG AA (4.5:1) on every background |
| 5.1.1(ii) consent | `PlayerEventsTests` (off until agreed, asked once, old unasked "on" is not consent); `PrivacyConsentUITests` (asked after the first game, never twice; privacy and support links in Settings) |
| HIG colour | Nam-Nam territory rings are solid or dashed, never colour alone |

## Not automatable: check by hand before each submission

In App Store Connect:
- **Paid Apps Agreement** active (banking, tax), and new in-app purchases **attached to the version**.
- **App Privacy** label matches the privacy manifest (Usage Data ▸ Product Interaction, Identifiers ▸
  Device ID, Purchases; not linked, not tracking, Analytics).
- **Accessibility Nutrition Labels**: declare what the app supports (VoiceOver, Larger Text,
  Sufficient Contrast, Reduced Motion, Differentiate Without Color). See the HIG accessibility page.
- **Screenshots** show the app in use (2.3.3), match each device size, and fit a 4+ rating (2.3.8).
- **Review notes** describe anything new "with specificity" (2.3.1(a)); generic notes are rejected.
- **Contact details** for App Review are current.

Outside App Store Connect:
- **Test on a real device** with the latest iOS (2.1). Simulators differ on sound, Reduce Motion and
  stored preferences.
- **TelemetryDeck**: delete usage statistics older than 12 months, as the privacy policy promises.
- **Cultural content** (1.1, HIG games: avoid stereotypes): Heritage, Journey names, Twi wording.
- **Third-party brands** (5.2.1) in any new text or art.

If a review is rejected: reply in App Store Connect's Resolution Center first; one appeal per
rejection; a bug-fix update with unrelated new issues can ship and fix those next time.
