# Lelu Oware: free vs paid, usage numbers and "sign-ups"

_Research note, 27 September 2026. Written for a solo indie developer before launch. Facts were checked against 2025–2026 sources, which are linked inline. Prices and quotas change, so check each vendor's page before you commit._

**Audience note (owner, 27 Sep 2026):** the game is for anyone who likes Oware, worldwide, not only Ghana and the diaspora. Read the Ghana-specific points (pricing, community channels) as one market among several.

**Decisions taken (27 Sep 2026):** free plus tips, no ads; online play to be a paid one-time unlock later, "the host pays"; Game Center, TelemetryDeck behind a toggle, and a website newsletter (Kit) are being built.

**Short answer:** Launch free with tips. Add Game Center, App Store Connect analytics and one privacy-first analytics SDK that needs no consent prompt. Also add an `AppTransaction` check now, so any later paywall can grandfather early players. Put a newsletter link on the website rather than inside the app. Delay every other decision until real numbers arrive.

---

## 1. Knowing how many people use it (no accounts)

### App Store Connect App Analytics (free, zero code)
- **Gives:** impressions, product page views, downloads, conversion rate, sources (search, browse, web referrer, campaign links), proceeds from tips, crashes, and (from 2025) cohorts, peer benchmarks and over 100 new metrics. [Apple: App Analytics](https://developer.apple.com/app-store-connect/analytics/) · [2025 overhaul summary](https://dev.to/tyson_cung/apple-just-overhauled-app-store-connect-100-new-metrics-for-developers-3he)
- **Limit:** *usage* metrics (sessions, active devices, retention) come only from users who opted into "Share with App Developers". Apple shows your opt-in rate, so treat these numbers as a sample, not a full count. [Apple: App usage](https://developer.apple.com/help/app-store-connect-analytics/engagement/app-usage) · [Opt-in docs](https://developer.apple.com/documentation/analytics-reports/app-store-opt-in)
- **Privacy label impact:** none. This is Apple's data, not yours.
- **Use campaign links** (`?pt=…&ct=tiktok`) on every social post so you can see which channel drives downloads.

### Game Center (free, light "identity")
- Leaderboards (for example, riddle streak or Journey stars), achievements, and from iOS 26 **Challenges** in the new Apple Games app, which also recommends games that friends are playing. That makes it a discovery channel, not just a scoreboard. [Apple Newsroom: Games app](https://www.apple.com/newsroom/2025/06/introducing-the-apple-games-app-a-personalized-home-for-games/) · [WWDC25: Get started with Game Center](https://developer.apple.com/videos/play/wwdc2025/214/)
- **Counts:** App Store Connect lets you view and manage the top 100 scores and players per live leaderboard. It does **not** give a clean "total players" dashboard. [Apple: Manage scores and players](https://www.developer.apple.com/help/app-store-connect/configure-game-center/manage-scores-and-players) Treat Game Center as engagement and virality, not a headcount.
- **Privacy:** Apple runs it under its own policy. If you do not send Game Center IDs to your own servers, most indies declare nothing extra. Your current policy already says you won't show the player ID. Update the "Game Center (future versions)" section when it ships.

### Third-party analytics SDKs compared

| Option | What leaves the device | Privacy label | ATT prompt? | Cost (2026) | Effort |
|---|---|---|---|---|---|
| **TelemetryDeck** (EU, Apple-focused) | Signals hashed and anonymised on-device, no personal data | Minimal: usually "Product Interaction, not linked to you". Vendor claims "trivial" | No | 100k signals/month free (free tier refreshes daily). Paid from about €9/month | SPM package plus about 10 lines. [Site](https://telemetrydeck.com/) · [Review](https://makerstack.co/reviews/telemetrydeck-review/) · [EU profile](https://euvetted.com/p/telemetrydeck) |
| **Aptabase** (open source) | No identifiers from the SDK. Server uses a daily-rotating hash | Vendor claims "Data Not Collected" is possible. Being conservative, declare Product Interaction, not linked | No | 20k events/month free. $10/month for 200k. Self-hostable | SPM package, manual `trackEvent`. [Pricing](https://aptabase.com/) · [Swift SDK](https://github.com/aptabase/aptabase-swift) |
| **PostHog** | Events plus an anonymous distinct ID. Profiles only if you `identify` | Product Interaction plus Identifiers (device-level), likely linked unless configured carefully | No (no IDFA) | 1M events/month free. Identified events cost about 4x anonymous ones | Heavier SDK, more features (funnels, flags, A/B tests). [Pricing](https://posthog.com/pricing) · [iOS personProfiles](https://posthog.com/docs/libraries/ios/usage) |
| **Firebase Analytics** | App-instance ID, device data, usage. IDFA if you let it | Product Interaction plus Device ID, linked. Heavier label | Only if IDFA is used, and many apps get pushed into ATT anyway | Free | Google SDK, privacy manifest work, and it would contradict the "no third-party SDKs" promise. [Firebase: App Store disclosure](https://firebase.google.com/docs/ios/app-store-data-collection) |

**Recommendation:** TelemetryDeck, or Aptabase if you want open source and lower lock-in. Both fit the "no gimmicks, respects you" brand. Firebase conflicts with your current privacy stance and gives little extra for a single-player game.

**Track only a handful of events:** `launch`, `game_finished{mode, level, result}`, `journey_chapter_completed{n}`, `riddle_solved`, `lesson_completed`, `tip_viewed`, `tip_purchased{tier}`. That is enough to answer "who plays, what, and does anyone reach the end".

### Consent design
- Apple does not need an ATT prompt for these tools, and anonymous aggregate analytics usually does not need GDPR consent. Even so, add a **Settings toggle "Share anonymous usage stats" (default on)** plus one line on first launch. It costs little, builds trust, and keeps you safe in the EU and UK.
- Wrap all analytics behind one `Analytics.track()` facade in the app. Then you can swap vendors, or turn analytics off, in one place.

### Privacy policy and nutrition label changes
Apple requires you to disclose data collected by third-party analytics SDKs. "Collect" means sending it off the device and keeping it. Processing that happens only on the device is not collection. [Apple: App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

- **Label (with TelemetryDeck or Aptabase):** *Data Not Linked to You → Usage Data → Product Interaction*, purpose *Analytics*. Add *Diagnostics → Crash Data* only if you send crashes. "Data Used to Track You" stays empty. You lose the "Data Not Collected" badge, which is the main cost.
- **Policy:** replace "no analytics, no third-party SDK" with a section that names the vendor. Say what is sent (anonymous gameplay events, app version, OS, country from IP that is then discarded), what is not sent (no name, email, ad ID or IP stored), where it lives, and that it can be switched off in Settings. Link to the vendor's DPA. Update the date.
- **Alternative if you want to keep "Data Not Collected":** rely on App Store Connect only for v1.0, then add the SDK in 1.1. You will have less insight in the launch window, which matters most.

---

## 2. Getting people to "sign up" for a free game

**The honest take:** for a free, offline, single-player game, a forced account hurts retention and adds no value. What you actually want is **a way to reach your fans later**, for a paid sequel, an online mode or a new game. Those fans can live outside the app.

| Method | UX cost | Privacy label cost | Worth it? |
|---|---|---|---|
| **Sign in with Apple** | A new screen, and the account then needs deletion support (Apple rule). Pointless without a server | Adds Contact Info (email, name, often a relay address), linked to you. Also needs a backend | **No** for v1. Revisit only if you add online play or cloud profiles. [Guidelines 4.8 / 5.1.1](https://developer.apple.com/app-store/review/guidelines/) |
| **Game Center** | Near zero. The system sign-in is already there for most users | Minimal | **Yes.** It is your "sign-up" with no form |
| **In-app email field** | Low if optional and placed after a win or in Settings | Adds *Contact Info → Email Address* to the label, because marketing email fails Apple's "optional disclosure" test | **Not inside the app.** Link out instead |
| **Newsletter on the website** (Buttondown, Kit or Mailchimp) linked from Settings, "About" and after finishing Journey | Tap a link and a web page opens | **None.** The data is collected on the web, not by the app | **Yes.** Cheap, you own the list, and the label stays clean |
| **Community** (WhatsApp Channel, TikTok, Instagram, Discord) | Just a link | None | **Yes, pick one or two** |

**Channel notes for Ghana and the diaspora:**
- WhatsApp is the most-used platform among Ghanaian internet users (93% in Q3 2024), and TikTok is second at about 81%. [Statista: Ghana social platforms](https://www.statista.com/statistics/1324588/favorite-social-media-platforms-in-ghana/) · [Statista: Social media in Ghana](https://www.statista.com/topics/9778/social-media-in-ghana/)
- A **WhatsApp Channel** fits best for announcements such as the daily riddle, new chapters and tournaments. It is one-way, members stay private from each other, and it is easy to forward.
- **TikTok** is for discovery: short clips of sowing and captures, "can you solve this riddle", and older players against the AI.
- **Discord** suits diaspora and hardcore players later. Skip it until there is demand, because an empty server looks worse than no server.
- Count followers and list sign-ups as your "users you can reach". Together with App Store Connect downloads, these are the numbers a publisher, Apple or a grant body will ask about.

---

## 3. Monetisation scenarios

Baseline facts:
- Enrol in the **App Store Small Business Program** before launch. Apple then takes 15% instead of 30% while your proceeds stay under $1M a year. [Apple: Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- Free-to-play still accounts for about 96% of mobile downloads. Premium mobile releases rose 77% in 2025, and a typical premium price is around $2.99–$4.99. [GameDev.net](https://gamedev.net/news/premium-mobile-games-are-back-with-releases-up-77-in-2025-r4367/) · [DEV: indie monetisation 2026](https://dev.to/linou518/indie-game-monetization-in-2026-premium-dlc-or-subscription-which-path-is-right-for-you-955)

### A. Free plus tips (current)
- **Pros:** maximum reach, including Ghana, where price sensitivity is high. Goodwill and on-brand. Tips via consumable IAP are explicitly allowed. [Guideline 3.1.1](https://developer.apple.com/app-store/review/guidelines/)
- **Cons:** tips usually convert well under 1% of players. Revenue depends on goodwill, not value delivered.
- **Revenue shape:** small, spiky around launches and features, long thin tail.
- **Switching later:** easiest starting point. Everything else can be layered on, *if* you can identify early players (see the `AppTransaction` section below).
- **Pitfall:** tips must not unlock anything. Keep "tips bring new features" as a statement of intent, not a promise that a tip buys a feature.

### B. Paid upfront ($2.99–$4.99)
- **Pros:** simple, honest, no IAP UI. Premium games are having a moment, and Arcade-style curators favour "pay once" games.
- **Cons:** downloads drop sharply, often by 10x or more. There is no way to try before buying. Ghanaian users often don't have App Store payment methods, so you lose your core audience.
- **Revenue shape:** a launch spike (bigger if featured), then decay. Price sales create bumps.
- **Switching:** paid to free is technically easy, but earlier buyers feel short-changed unless you grandfather them. Free to paid barely moves, because existing users keep the app and get updates.
- **Pitfall:** price changes apply straight away. Price-drop sites train users to wait for sales.

### C. Freemium with a one-time unlock (non-consumable)
Examples: "Journey chapters 4–10", "Board and seed collection (kente, ebony, brass)", or a single "Lelu Oware Complete" unlock. Keep AI, Pass & Play, the lesson and the daily riddle free forever.
- **Pros:** free reach plus a real product. Fits "no gimmicks" if sold as *one fair price, no ads, yours forever*. You can add a **free timed trial** as a $0 non-consumable named "XX-day Trial", which Apple allows for non-subscription apps. [Guideline 3.1.1](https://developer.apple.com/app-store/review/guidelines/) · [Apple forums, 2026](https://developer.apple.com/forums/thread/812511)
- **Cons:** you have to design the free and paid split. You need a paywall screen and Restore Purchases.
- **Revenue shape:** steady and proportional to downloads, typically 2–5% conversion for a well-liked game.
- **Switching:** easy to add later if early players are grandfathered. Hard to take away once sold.
- **Pitfall:** don't gate cultural core content such as the rules or the lesson. That would clash with the "teach Oware" mission and with reviews.

### D. Subscription
- **Pros:** recurring revenue. Apple's analytics now report subscription cohorts.
- **Cons:** Apple expects ongoing value in exchange (guideline 3.1.2). An offline board game rarely justifies it, and players resent it. It is also higher-effort: offers, churn, billing retries.
- **Fit:** poor now. It only makes sense later with online play, tournaments, or a *family of Ghanaian games* bundle.

### E. Ads
- **Pros:** monetises non-payers.
- **Cons:** ad SDKs mean heavy privacy labels, usually an ATT prompt, and they contradict the brand. Payouts for African traffic are low: rewarded eCPMs in lower-tier regions are around $2–4 against about $30 for US iOS, and missing ATT consent cuts eCPM by 60–80%. [RevenueLab: AdMob benchmarks 2026](https://www.revenuelab.fyi/blog/admob-ecpm-benchmarks-2026) · [Mistplay: eCPM data](https://business.mistplay.com/resources/mobile-ads-ecpm)
- **Verdict:** avoid. At most, a later opt-in rewarded ad for a cosmetic, and even that is off-brand.

### F. Apple Arcade
- Arcade is invite-only and curated. You can pitch via [developer.apple.com/apple-arcade](https://developer.apple.com/apple-arcade/), but Apple generally wants a track record or a proven App Store game. Deals are milestone funding, a buyout or licence, or (rarely) engagement-based royalties. [Medium: Arcade for indies](https://medium.com/@atnoforgamedev/developing-for-apple-arcade-what-indie-devs-need-to-know-4aca6d5b2294)
- Arcade games have **no ads and no IAP**. Existing hits can join as an "App Store Greats" "+" version, for example *Dead Cells+*. [App Store: No Ads or IAP](https://apps.apple.com/us/story/id1763284006) · [Wikipedia: Apple Arcade](https://en.wikipedia.org/wiki/Apple_Arcade)
- **Fit:** a realistic *upside* path if Lelu Oware gets good reviews, retention and press. Clean, ad-free, cultural and polished is exactly the kind of game Arcade features. Keep a build flag that strips tips and IAP so you can ship "Lelu Oware+" quickly.

### Summary

| Model | Reach | Revenue potential | Brand fit | Switch later |
|---|---|---|---|---|
| Free + tips | Highest | Low | Excellent | Easy base |
| Paid upfront | Low | Medium (spiky) | Good | Awkward |
| Freemium one-time unlock | High | Medium–high | Good if fair | Easy with grandfathering |
| Subscription | Medium | High but needs ongoing value | Poor now | Hard |
| Ads | High | Low (in Ghana) | Poor | Hard to remove goodwill damage |
| Apple Arcade | Arcade only | Lump sum | Excellent | Needs an invite |

---

## 4. The switching trap and how to avoid it

**The trap:** if you later add a paywall, players who downloaded when "everything was free" suddenly lose content, leave 1-star reviews and feel betrayed. If you go paid to free, early buyers feel they paid for nothing.

**The fix: StoreKit 2 `AppTransaction`, added now in v1.0.**
- `AppTransaction.shared` returns a signed, verified record including `originalAppVersion` and `originalPurchaseDate`. No server is needed. [Donny Wals: paid to freemium](https://www.donnywals.com/migrating-an-ios-app-from-paid-up-front-to-freemium/) · [FlineDev snippet](https://fline.dev/snippets/convert-paid-apps-freemium/) · [Pol Piella](https://www.polpiella.dev/paid-app-to-freemium)
- **Gotcha:** on iOS, `originalAppVersion` is the **build number (`CFBundleVersion`)**, not the marketing version. Use a monotonically increasing integer build number from day one, and record which build is "the last free-for-all build". [Apple forums](https://developer.apple.com/forums/thread/741347) In the sandbox and TestFlight it returns "1.0", so test the logic with a debug override.
- Requires iOS 16 or later, which is fine for a new app.
- **Pattern:** in v1.0, read and cache `AppTransaction` at launch, and store `isFounder = true` locally (with no UI). When you add an unlock, anyone whose `originalPurchaseDate` is before the cut-off, or whose `originalAppVersion` is at or below the last free build, gets it automatically. Call them **"Founding players"**, which is a nice, non-gimmicky thank-you.
- Also count people who tipped as supporters. Consumables aren't restorable, so keep a local and iCloud key-value flag, and simply treat all founders generously.
- Add **Restore Purchases** in Settings the moment any non-consumable exists.

---

## 5. Recommendation: set up to win without losing out

**Launch model:** free plus tips, with no ads and no accounts. Build the plumbing now for a **fair one-time unlock** later (for example Journey chapters beyond the first set, or premium boards), with founders grandfathered. Pitch Apple Arcade if the numbers get strong. Don't go paid upfront, don't use ads, and don't add a subscription.

**Why:** free maximises reach in Ghana and the diaspora, which is where word of mouth starts. Tips cost nothing to run. The `AppTransaction` check keeps every door open without upsetting early players. Aggregate analytics plus followers give you the numbers to decide, and to show Apple or partners.

**What to watch after 4–8 weeks** (decision triggers):
- If more than about 30% reach the end of Journey chapter 3 and D7 retention is above about 15%, there is enough engagement to sell more chapters or boards.
- If tip conversion is below 0.3% but retention is strong, add the one-time unlock.
- If you get strong reviews, featuring or press, write the Arcade pitch.

### Prioritised pre-launch checklist
1. **Enrol in the Small Business Program** (15% commission). 10 minutes.
2. **Add the `AppTransaction` founder check** and cache the result. Switch to integer build numbers and note the "last free build" in `docs/STATUS.md`.
3. **Integrate Game Center:** 2–3 leaderboards (riddle streak, Journey stars, wins against Master AI) plus a few achievements. Update the privacy policy's Game Center section.
4. **Add an analytics facade plus TelemetryDeck or Aptabase** with about 7 events and a Settings toggle. Update the privacy policy and set the label to "Usage Data → Product Interaction, not linked, analytics".
5. **Create App Store campaign links** for each channel (TikTok, WhatsApp, website, press).
6. **Add a website newsletter page** and link it from Settings and the end-of-Journey screen. No email field in the app.
7. **Open a WhatsApp Channel and a TikTok account.** Post the daily riddle and short gameplay clips.
8. **Add a hidden "Unlock / Restore Purchases" scaffold** behind a feature flag, so adding an IAP later is a small update.
9. **Add an "Arcade build" flag** that removes the tip jar, for a possible "+" version.
10. **Plan pricing tests for later:** use App Store product page optimisation to A/B test screenshots and icon. When the unlock exists, try country-specific prices (for example lower in Ghana) and compare conversion in App Analytics.

---

### Sources
- Apple: [App Analytics](https://developer.apple.com/app-store-connect/analytics/), [App usage metrics](https://developer.apple.com/help/app-store-connect-analytics/engagement/app-usage), [App Store opt-in](https://developer.apple.com/documentation/analytics-reports/app-store-opt-in), [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Small Business Program](https://developer.apple.com/app-store/small-business-program/), [Manage leaderboard scores/players](https://www.developer.apple.com/help/app-store-connect/configure-game-center/manage-scores-and-players), [WWDC25 Game Center](https://developer.apple.com/videos/play/wwdc2025/214/), [Games app announcement](https://www.apple.com/newsroom/2025/06/introducing-the-apple-games-app-a-personalized-home-for-games/), [AppTransaction forum thread](https://developer.apple.com/forums/thread/741347), [$0 trial forum thread](https://developer.apple.com/forums/thread/812511), [Arcade: No Ads or IAP](https://apps.apple.com/us/story/id1763284006)
- Analytics vendors: [TelemetryDeck](https://telemetrydeck.com/), [TelemetryDeck review 2026](https://makerstack.co/reviews/telemetrydeck-review/), [Aptabase](https://aptabase.com/), [aptabase-swift](https://github.com/aptabase/aptabase-swift), [PostHog pricing](https://posthog.com/pricing), [PostHog iOS](https://posthog.com/docs/libraries/ios/usage), [Firebase App Store disclosure](https://firebase.google.com/docs/ios/app-store-data-collection)
- Market: [Premium mobile releases up 77% (2025)](https://gamedev.net/news/premium-mobile-games-are-back-with-releases-up-77-in-2025-r4367/), [Indie monetisation 2026](https://dev.to/linou518/indie-game-monetization-in-2026-premium-dlc-or-subscription-which-path-is-right-for-you-955), [AdMob eCPM benchmarks 2026](https://www.revenuelab.fyi/blog/admob-ecpm-benchmarks-2026), [Mistplay eCPM](https://business.mistplay.com/resources/mobile-ads-ecpm), [Statista: Ghana platforms](https://www.statista.com/statistics/1324588/favorite-social-media-platforms-in-ghana/)
- StoreKit migration guides: [Donny Wals](https://www.donnywals.com/migrating-an-ios-app-from-paid-up-front-to-freemium/), [FlineDev](https://fline.dev/snippets/convert-paid-apps-freemium/), [Pol Piella](https://www.polpiella.dev/paid-app-to-freemium)
- Arcade: [Medium guide](https://medium.com/@atnoforgamedev/developing-for-apple-arcade-what-indie-devs-need-to-know-4aca6d5b2294), [Wikipedia](https://en.wikipedia.org/wiki/Apple_Arcade)
