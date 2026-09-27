# Lelu Oware: business model, services and launch setup

Reference for everything outside the game itself: how the app makes money, what it measures, which
outside services it uses, and what has to be set up in each. Last updated 27 September 2026.

Background research, with sources: [`../../../docs/research/free-vs-paid.md`](../../../docs/research/free-vs-paid.md)
(kept off the public website).

## Accounts and IDs

None of these are secrets: they are identifiers that ship inside the app or appear in public
settings. Passwords, API keys and certificates never go in this repo.

| Service | Item | Value |
|---|---|---|
| Apple Developer | Team ID | `2H3QQFZLL3` (also `export DEVELOPMENT_TEAM=2H3QQFZLL3` in `~/.zshrc`) |
| App Store Connect | App name | Lelu Oware |
| App Store Connect | Bundle ID | `com.richardforjoe.oware` (free-account family builds: `com.richardforjoe.oware.family`) |
| App Store Connect | SKU | `oware-ios` |
| App Store Connect | Primary language | English (U.K.) |
| App Store Connect | Apple ID (numeric) | App Information page; add it here once the app record exists |
| TelemetryDeck | App ID | `2B02636D-AE8C-4D55-A14A-9FCDE1C25D74` (in `project.yml` as `TELEMETRYDECK_APP_ID`) |
| TelemetryDeck | Organisation namespace | `lelu.oware`. Not set in the app: TelemetryDeck's Swift guide needs only the App ID, and the SDK advises leaving the namespace unset |
| TelemetryDeck | Dashboard | https://dashboard.telemetrydeck.com/o/9F5A8F6A-76C1-494D-A0E0-0B00D0C532B2/apps/2B02636D-AE8C-4D55-A14A-9FCDE1C25D74/setup-helper |
| GitHub Pages | Site | https://richardforjoejnr.github.io/oware/lelu-oware/ |
| Kit | Newsletter form | not created yet (see section 6) |

## 1. Decisions

| Topic | Decision (27 Sep 2026) |
|---|---|
| Price | Free to download. No adverts, ever. |
| Money | Optional tips ("Support me"): three consumable in-app purchases that unlock nothing. |
| Paid features | Online play, when it ships, is a **one-time "Play online" unlock**. **The host pays**: a player who has it can invite anyone, and invited friends play that match free. |
| Early players | "Founding players" (installed before something became paid) can be given it free with one switch. Off by default for online play. |
| Audience | Anyone who likes Oware, worldwide. The Ghanaian board and craft are the identity, not a limit on the market. |
| Accounts | None. Game Center is the only "sign-in", and it is optional. |
| Email | Never asked for in the app. A newsletter sign-up lives on the website. |
| Measurement | App Store Connect analytics (downloads, sources) plus anonymous in-app events through TelemetryDeck, which players can switch off. |

## 2. Where it lives in the code

| Piece | File | Notes |
|---|---|---|
| Tip jar | `packages/SupportKit/…/TipJar.swift`, `TipJarView.swift` | Shown from Settings ▸ Support me. |
| One-time unlock | `packages/SupportKit/…/Unlock.swift` | Non-consumable; reads StoreKit entitlements; caches the answer. |
| Founding players | `packages/SupportKit/…/FoundingPlayer.swift` | StoreKit 2 `AppTransaction.originalAppVersion` (the first-installed **build number**). |
| Online rules | `Oware/Sources/Support/OnlineAccess.swift` | `FeatureFlags.onlinePlay` (off), `OnlinePolicy` (host pays), product id. |
| Online match data | `packages/OwareEngine/…/OnlineMatch.swift` | Rules + houses played; every copy replayed through the engine; versioned; under 64 KB. |
| Analytics | `Oware/Sources/Support/Analytics.swift` | One facade (`Analytics.shared.track`), TelemetryDeck backend. |
| Game Center | `Oware/Sources/Support/GameCenter.swift`, `Oware/Oware.entitlements` | Sign-in, leaderboards, achievements, dashboard. |
| What each moment reports | `Oware/Sources/Game/PlayerEvents.swift` | Maps games, riddles, Journey, lesson and tips to analytics and Game Center. |
| Riddle streak | `Oware/Sources/Game/PuzzleLibrary.swift` | Days in a row the daily riddle was solved. |
| Web links | `Oware/Sources/Support/Links.swift` | Website, newsletter, privacy. |
| Public pages | `../../../docs/lelu-oware/` | `privacy.md`, `support.md`, `newsletter.md` (GitHub Pages). |

Nothing is sent and no sheet appears in test launches (`--fast-animations`), so the XCUITest,
Appium and Maestro suites are unaffected.

## 3. Game Center

Set up in **App Store Connect ▸ your app ▸ Features ▸ Game Center**. Ids must match exactly.

| Kind | Id | Meaning | Setup |
|---|---|---|---|
| Leaderboard | `com.richardforjoe.oware.leaderboard.riddleStreak` | Days in a row solving the daily riddle | Classic, best score, integer, high to low |
| Leaderboard | `com.richardforjoe.oware.leaderboard.journeyStars` | Total Journey stars | Classic, best score, integer, high to low |
| Leaderboard | `com.richardforjoe.oware.leaderboard.grandmasterWins` | Wins against the Grandmaster level | Classic, best score, integer, high to low |
| Achievement | `com.richardforjoe.oware.achievement.firstWin` | Win any game against the computer or in the Journey | |
| Achievement | `com.richardforjoe.oware.achievement.lessonDone` | Finish the lesson | |
| Achievement | `com.richardforjoe.oware.achievement.firstRiddle` | Solve a riddle | |
| Achievement | `com.richardforjoe.oware.achievement.firstChapter` | Complete a Journey chapter | |
| Achievement | `com.richardforjoe.oware.achievement.beatGrandmaster` | Beat the Grandmaster | |
| Achievement | `com.richardforjoe.oware.achievement.allTwelveHouses` | Win a Nam-Nam game by holding all twelve houses | |

Game Center does not give a total player count; use App Store Connect analytics for numbers.

## 4. Analytics (TelemetryDeck)

- **Switch:** Settings ▸ "Share anonymous usage stats", on by default. Off stops every event.
- **Configured (27 Sep 2026):** `TELEMETRYDECK_APP_ID` in `project.yml` holds the App ID of the
  TelemetryDeck app "Lelu Oware". Setting it back to empty turns analytics off entirely.
- **Free tier:** 100,000 signals a month. Debug builds are marked as test data automatically.

| Event | Parameters | When |
|---|---|---|
| `app.launched` | none | Each launch |
| `game.finished` | `mode` (computer, journey, passAndPlay), `level`, `result` (win, loss, draw, or A/B for two players), `rules` (namNam, abapa) | A game ends |
| `journey.chapterCompleted` | `chapter` | Every opponent in a chapter beaten for the first time |
| `riddle.solved` | `kind`, `daily` (yes/no) | A riddle is solved |
| `lesson.completed` | `rules` | The last lesson step is reached |
| `tipJar.viewed` | none | The Support me sheet opens |
| `tipJar.purchased` | `tier` (small, medium, large) | A tip goes through |

Adding an event: add a case to `AnalyticsEvent`, fire it from `PlayerEvents`, extend
`PlayerEventsTests.testEventsCarryNoPersonalData`, and update this table and the privacy policy.

## 5. App Store Connect: App Privacy label

Replaces the earlier "Data Not Collected" answer once analytics ship.

| Data type | Linked to the user? | Used for tracking? | Purpose |
|---|---|---|---|
| Usage Data ▸ Product Interaction | No | No | Analytics |
| Identifiers ▸ Device ID | No | No | Analytics |

The Device ID row is there because TelemetryDeck's own privacy manifest declares a hashed device
id. Game Center data is handled by Apple under its own policy and is not declared by the app. If
`TELEMETRYDECK_APP_ID` is left empty at submission, the app collects nothing and "Data Not
Collected" is still correct.

## 6. Newsletter (Kit)

- **Why Kit:** free up to 10,000 subscribers, unlimited forms, one-click unsubscribe. (MailerLite's
  free plan fell to 250 subscribers in June 2026; Buttondown's is 100.)
- **Setup:** create a free Kit account, then a form (Grow ▸ Landing Pages & Forms). Under Publish ▸
  JavaScript, copy the `data-uid` and the script URL into the front matter of
  `docs/lelu-oware/newsletter.md` (`kit_form_uid`, `kit_form_script`). Until then the page says
  sign-ups open soon.
- **Links in the app:** Settings ▸ "News by email", and "Hear about new chapters" on the result
  screen after the last Journey match.
- **Page:** https://richardforjoejnr.github.io/oware/lelu-oware/newsletter

## 7. App Store Small Business Program

- **Cost:** free. It is a separate enrolment, not automatic with the Developer Program.
- **Who:** the Account Holder of a paid Apple Developer Program membership, earning under
  US$1 million in proceeds a year (new developers qualify).
- **Effect:** Apple's commission on tips and any future unlock drops from 30% to 15%, from 15 days
  after the end of the fiscal month in which enrolment is approved.
- **Where:** https://developer.apple.com/app-store/small-business-program/

## 8. Online play (built, not shown)

What exists:
- `OnlineMatch`: the match message (rules + houses played + resignation), validated by replay so a
  tampered or out-of-date message is refused, with a format version.
- `Unlock` for the product `com.richardforjoe.oware.online` (in `Tips.storekit` for local testing
  only; not yet in App Store Connect).
- `OnlinePolicy` / `OnlineAccess`: who may host and who may join.

Still to build when online ships:
1. Matchmaking and turns with Game Center turn-based matches (`GKTurnBasedMatch`), sending
   `OnlineMatch.encoded()` as the match data.
2. The screens: an Online tile, the purchase sheet, invites.
3. The product in App Store Connect, and `FeatureFlags.onlinePlay = true`.
4. Privacy policy and label updates for online play.
5. Decide `OnlinePolicy.foundingPlayersIncluded`, and set `OnlineProduct.lastFreeBuild` if early
   players get it free.

## 9. Build numbers

StoreKit reports the **build number** (CFBundleVersion) a player first installed, and the founding
check compares it as an integer. Keep `CURRENT_PROJECT_VERSION` in `project.yml` a plain increasing
integer, and record the last build before anything becomes paid. The sandbox and TestFlight report
"1.0"; the check treats that as founding.

## 10. Owner checklist

The full ordered list, including TestFlight and submission, is [ACTION_LIST.md](ACTION_LIST.md).

- [ ] Enrol in the Small Business Program.
- [ ] Game Center: enable it for the app; create the 3 leaderboards and 6 achievements above.
- [ ] TelemetryDeck: create an account and app; put the App ID in `project.yml`.
- [ ] App Privacy label as in section 5.
- [ ] Kit: create the form; paste its values into `newsletter.md`.
- [ ] Support email in `docs/lelu-oware/*.md` (privacy and support pages).
- [ ] Tips: the three consumables in App Store Connect (see `APP_STORE.md`).
