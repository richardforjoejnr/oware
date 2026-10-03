# App Store listing — draft

Everything App Store Connect asks for, ready to paste. Owner to review wording and fill the
bracketed items.

## Identity
- **Name:** Lelu Oware
- **Subtitle (30):** The seed game of Ghana
- **Bundle ID:** com.richardforjoe.oware · **SKU:** oware-ios
- **Primary category:** Games › Board · **Secondary:** Games › Strategy
- **Age rating:** 4+ (no objectionable content; answer "No" to every questionnaire item)
- **Price:** Free, no ads. Three optional **tip** in-app purchases (consumable; they unlock nothing).
- **Availability:** all countries (for anyone who likes Oware). Online play, later, is planned as a
  paid one-time unlock; see [SERVICES.md](SERVICES.md).
- **Privacy policy URL:** https://leluoware.com/lelu-oware/privacy · **Support URL:** https://leluoware.com/lelu-oware/support (AWS S3 + CloudFront, built from `docs/lelu-oware/*.md` by the Site workflow)

## Promotional text (170)
Oware as it is played in Ghana, on a hand-finished board. Nam-Nam or tournament Abapa, four computer levels, daily riddles and a Journey across Ghana. Free, no ads.

## Description
Oware is one of the world's oldest board games: two rows of six houses, forty-eight seeds, and the rule that you always leave your opponent something to play. Lelu Oware brings it to your phone with the feel of a Ghanaian board: carved wood, stone-grey seeds that drop into each house as you sow, and the calm of an evening game in the shade.

PLAY
- Nam-Nam, the game Ghanaian children learn first: seeds roam from house to house, you capture by making four, and every round wins or loses you houses until one player holds all twelve.
- Or switch to Abapa, the tournament rules: captures on twos and threes, first to 25 seeds.
- Four computer levels, from Novice to Grandmaster.
- Pass & Play with a friend on one device.
- Long-press any house to see where your last seed will land. Undo and hints when you want them.

LEARN
- A short lesson with Nana that shows instead of tells.
- Ananse's riddles: dozens of positions with one right answer, and a new riddle every day. Keep your streak going.
- Rules and heritage: where the game comes from, its many names across West Africa and the Caribbean, and what Nam-Nam means.

JOURNEY
- Eight places across Ghana, from Kumasi to Tamale, each with three opponents who play in their own way.
- Earn stars to open the next chapter. Every chapter is free.

Leaderboards and achievements with Game Center.

Free, with no ads and no account. Optional tips support the maker and unlock nothing. Anonymous usage statistics help decide what to make next, and you can switch them off in Settings.

Akwaaba.

## Keywords (100)
awale,mancala,ayo,warri,nam-nam,abapa,board game,strategy,seeds,african,ghana,riddles,family,offline

(The app name is already searched, so "Lelu" and "Oware" are not repeated here.)

## URLs, version and copyright
- **Support URL:** https://leluoware.com/lelu-oware/support
- **Marketing URL:** leave empty for now (optional).
- **Version:** 1.0 · **Copyright:** 2026 Richard Forjoe
- **Routing App Coverage File:** leave empty (only for navigation apps).

## App Review Information
- **Sign-in required:** untick. The app has no accounts.
- **Contact:** your name, phone and email (seen only by Apple's reviewers).
- **Notes:** "No login is needed. The three in-app purchases are optional tips; they unlock nothing,
  and every level, chapter and board look is available to all users. Game Center is optional. The
  game works fully offline. Anonymous usage statistics (TelemetryDeck) can be switched off in
  Settings. Cultural content is traditional (Adinkra symbols, Kente colours); artwork is original."

## What's new (1.0)
First release.

## In-app purchases — tip jar

The game is entirely free; the only purchases are tips (decided 2026-09-26, replacing the earlier
"Full Journey" unlock). Create three **Consumable** products in App Store Connect:

| Product ID | Reference name | Display name | Description | Tier |
|---|---|---|---|---|
| `com.richardforjoe.oware.tip.small` | Tip (small) | Small tip | A small thank-you to the maker. | ~£0.99 |
| `com.richardforjoe.oware.tip.medium` | Tip (medium) | Medium tip | A medium thank-you to the maker. | ~£2.99 |
| `com.richardforjoe.oware.tip.large` | Tip (large) | Generous tip | A generous thank-you to the maker. | ~£4.99 |

Review note: "The in-app purchases are optional tips. They unlock no content; every level, chapter
and board look is available to all users." Local testing uses `Oware/Resources/Tips.storekit`.

## App Privacy (nutrition label)
- With analytics configured (`TELEMETRYDECK_APP_ID` set): Usage Data ▸ Product Interaction and
  Identifiers ▸ Device ID, both not linked to the user, not used for tracking, purpose Analytics.
- With `TELEMETRYDECK_APP_ID` empty: **No, we do not collect data from this app.**
- Details: [SERVICES.md](SERVICES.md) section 5.

## Screenshots (to produce from the simulator, see `e2e/specs/screenshots.spec.ts`)
Required sizes: 6.9" iPhone (1320×2868), 13" iPad (2064×2752). Order:
1. Board mid-game (portrait) — "Carved osese wood, real nickernut seeds"
2. Long-press landing preview — "See where your last seed lands"
3. Learn with Nana — "Learn in five minutes"
4. Ananse's riddles — "A new riddle every day"
5. Journey — "From Kumasi to Tamale"
6. Heritage — "Ghana's game, told properly"

## Review notes for Apple
See "App Review Information" above. Tips can be tested with the local StoreKit configuration or a
sandbox account.
