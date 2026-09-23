# Oware for iOS — Game Plan (v0.1, for approval)

Working title: **Oware: Seeds of Ghana** (alternatives: *Ɔware*, *Oware Kingdom*, *Nana's Oware*).
Status: DRAFT — awaiting owner approval. Date: 2026-09-23.

---

## 1. Vision

A beautifully crafted, App Store-ready Oware game whose *feel* is the product: seeds that sow with
rhythm, weight and sound; rules that are exactly right (Abapa tournament rules, with every edge case
handled); and an art direction rooted in real Ghanaian visual culture (Kente, Adinkra, carved osese
boards, Asante gold weights, talking drums) rather than a generic "wooden mancala" look.

Three pillars, in priority order:

1. **Mechanics first.** Rules engine is a standalone, fully-tested Swift package. Sowing, captures,
   grand slam, feeding obligation, endgame and cycle detection all correct and deterministic.
2. **Feel.** Per-seed sowing animation, haptic tap per seed, drum-based audio, capture celebrations,
   landing-spot preview, undo/takeback. Smooth on iPhone SE through iPhone Pro Max and iPad.
3. **Ghana, authentically.** Every colour, symbol, name and sound is sourced and its meaning is
   explained in-app. Cultural content is respectful (e.g. the Golden Stool is never used as a
   trophy/prop).

---

## 2. Research summary

### 2.1 The rules we will implement (Abapa — "the proper version")

Sources: Masters of Games rules page, oware.org Abapa page (The Oware Society), bead.game, Wikipedia.

| Rule | Implementation |
|---|---|
| Board | 2 rows × 6 houses, 48 seeds, 4 per house. Two stores (score houses) at the ends. |
| Turn | Pick a non-empty house on your side; scoop all seeds; sow one per house counter-clockwise, starting with the next house. Stores are never sown into. |
| 12+ seeds | The origin house is skipped on every lap (12th and 23rd seed go past it). Origin always ends empty. |
| Capture | If the **last** seed lands on the opponent's side and makes that house **2 or 3**, capture it. Then walk backwards (clockwise) capturing consecutive opponent houses that are also 2 or 3; stop at the first house that isn't, or at the end of the opponent's row. Never capture on your own side. |
| Grand slam | If a move would capture **all** of the opponent's seeds, the move is legal but the capture is forfeited (international tournament rule; also bead.game). Ruleset toggle for the two other common variants (illegal move / capture allowed and game ends). |
| Feeding | If the opponent's side is empty at the start of your turn you **must** play a move that sows into their side if any such move exists. If none exists, you capture all seeds on your side and the game ends. |
| Win | First to 25 wins. 24–24 is a draw. |
| Cycle / stalemate | When play can only go round in circles, each player keeps the seeds on their side. Engine detects: (a) position repeated 3 times, or (b) N moves with no capture where total seeds on board ≤ threshold; then offers "end game — each keeps their side" (auto-applied vs AI, agreed via prompt in PvP). |
| First move | Coin toss in game 1; winner of previous game starts next (tournament convention). Toggle. |

Unit tests will cover every row above, plus a full-game replay format (move notation `A1…A6 / B1…B6`)
so bug reports are reproducible.

Optional rule variants (later, behind a toggle, off by default): Nam-Nam (Ghanaian children's
version), Kalah for people who know "Mancala". Core release ships Abapa only to keep focus.

### 2.2 What existing apps do (and where we'll be different)

| App | Strengths | Weaknesses we can beat |
|---|---|---|
| **Awale Online** (4.6★, 29 ratings) | Strong AI (7 levels), Game Center rated online, study mode | 220 MB, dated UI, 30-second ad interstitials, subscription pricing, generic look |
| **Oware Master** (4.7★, 1.1K ratings) | 3D board, 5 AI levels | Last updated Aug 2022, reported freezes, no undo, steep difficulty jumps, iPad-first |
| **Awele/Oware Mancala HD** | Nice sounds, 5 themes | Old, minimal features |
| **Mancala Adventures** | Progression map, bosses, cosmetics — popular formula | It's Kalah, not Oware; power-ups break the game; generic cartoon art |
| **PlayOK / playawale.com (web)** | Free online play | Not native, no polish |

**Our differentiators**

1. **Authentic Ghanaian art direction** — nobody in this space does it. Kente palette, Adinkra
   iconography with real meanings, carved-wood board with Asante motifs, nickernut seeds.
2. **Best-in-class feel** — per-seed animation + haptics + drum audio; long-press a house to preview
   the sowing path and landing house (with capture highlight); undo/takeback in casual modes.
3. **Progression without power-ups** — a "Journey across Ghana" campaign with character opponents
   (each with a distinct AI *personality*), rewards are cosmetic (boards, seeds, Kente patterns).
   Mechanics stay pure Abapa, which is the tournament game.
4. **Learn from the Elder** — interactive tutorial + puzzle mode ("Ananse's Riddles": capture-in-1,
   capture-in-2, escape-the-trap, feed-or-lose) + a daily puzzle.
5. **No forced ads.** Free core game, one-time IAP (details in §7).
6. **Small and fast** — target < 60 MB, offline-first, iOS 17+, 120 Hz where available.
7. **Online play with zero accounts** via Game Center turn-based matches (no servers, no login).

### 2.3 Ghanaian culture — what we'll use and how

**The game itself.** Oware (Twi: *Ɔware*) is regarded as the national game of the Asante and Bono
peoples and is played across West Africa and the Caribbean under many names (Awale, Ayo, Warri,
Adji [Ewe], Awele [Ga]). The name is popularly linked to *ware* = "to marry": one tradition says a
couple played so endlessly they married so they could keep playing; another credits Asantehene
Opoku Ware I (r. c. 1720–1750) with using the game to reconcile quarrelling couples. Spectators
traditionally advise players — Oware is famously social. Boards are carved from osese wood, often
on a stool base or animal (elephant) plinth; seeds are nickernuts (*Caesalpinia bonduc*), grey and
shiny. We'll tell these stories in a "Heritage" section, phrased as tradition ("it is said…"), not
as historical fact.

**Colour — Kente meanings** (used as the app palette and explained in-app):
gold = royalty/wealth; black = maturity/ancestral strength; green = growth/renewal;
red = sacrifice/passion; blue = peace/harmony; white = purity/festivity. Named Kente patterns
(e.g. *Adweneasa*, *Oyokoman*, *Sika Futuro*, *Emaa Da*) become unlockable board/border skins.

**Adinkra symbols as UI language** (we draw our own vectors; meanings shown on tap):

| Symbol | Meaning | Where it appears |
|---|---|---|
| Sankofa (bird) | "Go back and fetch it" — learn from the past | Undo / game history / replay |
| Nyansapo (wisdom knot) | Wisdom, ingenuity | Hints, tutorial, puzzles |
| Adinkrahene | Greatness, leadership | Rank / leaderboard |
| Dwennimmen (ram's horns) | Strength with humility | AI difficulty |
| Funtunfunefu-Denkyemfunefu (Siamese crocodiles) | Unity in diversity | Multiplayer |
| Eban (fence) | Safety, security | "Protected house" indicator |
| Nkyinkyim | Twists, adaptability | Puzzle mode |
| Mate Masie | "What I hear, I keep" | Settings / saved games |
| Aya (fern) | Endurance | Achievements / streaks |
| Akoma (heart) | Patience, tolerance | Draw / stalemate offer |

Gye Nyame (supremacy of God) is the most famous symbol; we will use it only in the Heritage section
with its meaning, not as a button icon — it carries religious weight.

**Sound.** Atumpan (talking drum) taps for seed drops and turn changes, fontomfrom hit for
captures/wins, soft highlife/kpanlogo-inspired original loop for menus. All audio original or CC0.

**Words** (verified common usage): *Akwaaba* (welcome), *Medaase* (thank you), *Ayekoo* (well done),
*Nana* (elder/chief honorific). Twi phrases used sparingly, always with English.

**Journey map across Ghana** (campaign chapters, each with an opponent character + board skin):
Kumasi (Manhyia, Adinkra) → Bonwire (Kente weavers) → Lake Bosomtwe → Techiman/Bono (Oware's other
home) → Cape Coast (coast, cowrie seeds) → Accra/Makola market (Ga *awele*) → Volta (Ewe *adji*) →
Mole/Tamale (north, Dagbani *wali*). Opponent characters are respectful archetypes (market trader,
weaver, fisherman, teacher, elder), never caricatures.

**Cultural safeguards.** No depiction of the Golden Stool (*Sika Dwa*) as a game object; no sacred
regalia as loot; every symbol meaning cross-checked against ≥2 sources; proverbs used only from a
verified list with translations; we'll ask a Ghanaian reviewer (ideally you or someone you know)
to review the Heritage text before release.

---

## 3. Game design

### 3.1 Modes
- **Quick Play vs AI** — 6 levels: Beginner, Learner, Player, Strong, Master, Grandmaster.
- **Pass & Play** — two people, one device; "table mode" flips the opponent's HUD; portrait & landscape.
- **Journey** — 8 chapters × ~5 matches; opponent personalities (aggressive, hoarder, patient, tricky);
  stars for win / win by margin / win without conceding a capture chain; cosmetic unlocks.
- **Learn** — interactive 5-minute tutorial ("Learn from Nana"), then rules reference.
- **Puzzles** — 60 hand-made puzzles + daily puzzle (seeded by date, offline).
- **Online** — Game Center turn-based (async, push notified), plus friend invites. Leaderboards
  (Journey stars, puzzle streak) and achievements.

### 3.2 The turn — feel spec
1. Tap or long-press a house. Long-press shows the sowing path, the landing house, and any
   capture chain, ghosted. Release to play, slide off to cancel.
2. Seeds fly out one by one (~70 ms apart, ease-out arc), a soft drum tap + light haptic per seed.
   Speed scales with seed count so a 20-seed sow still finishes in < 2.5 s. Setting: fast/normal/slow.
3. Captures: houses pulse gold, seeds sweep into the store with a fontomfrom hit and a stronger haptic.
4. Grand-slam forfeit and feeding obligation are explained in a one-line toast the first time they
   occur ("Capture forfeited — you may not leave Nana with nothing").
5. Illegal houses (empty, or ones that fail the feeding rule) are dimmed with a reason on tap.
6. Undo (Sankofa) available vs AI and in Pass & Play if both agree; not in Online or Puzzles.
7. Store counts always visible; seeds in a house shown as real seeds up to 12, then seeds + number.

### 3.3 AI
- Minimax with alpha-beta, iterative deepening, transposition table, move ordering (captures first).
- Evaluation: store difference, seeds on own side, mobility, vulnerable houses (1–2 seeds facing a
  reachable last-seed), accumulating "kroo" houses (12+), feeding safety.
- Difficulty = search time budget + depth cap + a small random error rate at low levels so
  Beginner is genuinely beatable. Runs off the main thread with a 0.3–2.0 s think time.
- Personalities reweight the evaluation (e.g. "Aggressive" over-values captures).

### 3.4 Progression & cosmetics (all cosmetic, none affect rules)
Boards (osese wood, ebony, stool-base, market cloth), seed sets (nickernuts, cowries, palm kernels,
glass beads), Kente border patterns, Adinkra stamps for your profile.

---

## 4. Technical plan

- **Language/UI:** Swift 6, SwiftUI app shell (menus, Journey, settings, Heritage).
- **Board:** SpriteKit scene hosted in `SpriteView` for the board, seeds, particles, 120 Hz
  animation; deterministic animation driven by engine events.
- **Engine:** `OwareEngine` Swift package, zero UI deps, `Sendable` value types, exhaustive tests.
  Public API: `GameState`, `Move`, `RuleSet`, `apply(move) -> [Event]` (sow, skip, capture, forfeit,
  feed, gameOver), `legalMoves()`, `notation`.
- **AI:** `OwareAI` package on top of the engine, async, cancellable.
- **Persistence:** SwiftData/JSON in app container for saves, Journey progress, settings; iCloud
  key-value sync for progress (optional).
- **Online:** GameKit `GKTurnBasedMatch`; match state = compact engine state + move list.
- **Audio/haptics:** AVAudioEngine, CoreHaptics (with fallbacks).
- **Accessibility:** VoiceOver labels per house ("Your house 3, five seeds"), Dynamic Type, Reduce
  Motion (instant sow), colour-blind-safe capture highlights, no colour-only information.
- **Min iOS:** 17.0. Devices: iPhone + iPad (universal). Landscape + portrait.
- **Repo layout:**
  ```
  Oware.xcodeproj / Oware (app target)
  Packages/OwareEngine, Packages/OwareAI
  Resources/ (Assets.xcassets, Audio, Localizable.xcstrings)
  docs/ (this plan, rules, cultural sources, privacy policy source)
  ```
- **Tooling:** XcodeGen or plain project; SwiftLint; unit + UI tests; TestFlight from day one.

---

## 4b. Delivery pipeline (repo → TestFlight → App Store)

Set up in this repo (see `docs/PIPELINE.md` for the one-time credentials you must provide):
- **PR → CI**: engine tests + unsigned simulator build/test on GitHub's macOS runners. Required to merge.
- **Merge to main → TestFlight**: fastlane builds a signed Release and uploads it; build number = CI run number.
- **GitHub Release `vX.Y.Z` → App Store Connect**: upload + optional submit-for-review behind a manual approval gate.
- Signing via fastlane *match* (certs in a private repo); App Store Connect API key for uploads; no passwords in CI.

## 5. App Store compliance plan (must pass first time)

| Guideline | What we do |
|---|---|
| 2.1 Completeness | No placeholders; all URLs live; crash-free on device matrix before submit. |
| 2.3 Metadata | Screenshots from the real app; IAP clearly described; age rating 4+. |
| 2.5.1 APIs | Public APIs only; Game Center/StoreKit used for their intended purpose. |
| 3.1.1 IAP | All unlocks via StoreKit 2; Restore Purchases button; nothing expires. |
| 4.1 / 4.3 Copycat & spam | Original name, icon, art, code; clear differentiation (§2.2). |
| 4.2 Min functionality | Full game + AI + tutorial + puzzles + campaign — well above bar. |
| 4.5.3 / 4.5.5 Game Center | No spam invites; never display Player IDs. |
| 5.1.1 Privacy | No account; no third-party analytics/ads → privacy label "Data Not Collected"; privacy policy URL in metadata and in Settings. |
| 5.1.2 Tracking | No tracking, so no ATT prompt needed. |
| 5.2 IP | All art drawn by us/commissioned; Adinkra/Kente are traditional but our vectors are original; fonts licensed (SF + one licensed display font); audio original/CC0; no third-party brand names (e.g. we don't reference "The Oware Society"). |
| Kids Category | Not applying (avoids extra constraints) but content is 4+ safe. |
| Also | Export compliance flag (no custom crypto), support URL, EULA default, localisation of metadata. |

---

## 6. Milestones

| # | Milestone | Deliverable | Est. |
|---|---|---|---|
| 0 | Approval & art direction | This plan approved; moodboard (palette, board, symbols, type) | 1–2 days |
| 1 | Engine | `OwareEngine` package, 100% rule coverage tests, replay notation, CLI self-play | 3–4 days |
| 2 | Playable core | Xcode project, board scene, sowing/capture animation, Pass & Play, AI (levels 1–4), save/resume; TestFlight build #1 | 1–2 weeks |
| 3 | Learn & Puzzles | Tutorial, 60 puzzles, daily puzzle, rules reference, Heritage section | 1 week |
| 4 | Journey | 8 chapters, personalities, cosmetics, achievements | 1–2 weeks |
| 5 | Online | Game Center turn-based, leaderboards; Master/Grandmaster AI | 1 week |
| 6 | Polish & ship | Audio, haptics, accessibility, iPad layouts, localisation (EN first), App Store assets, privacy policy, submission | 1 week |

Each milestone ends with a TestFlight build you can play.

---

## 7. Open decisions (need your answer)

1. **Monetisation** — recommended: free, no ads, one-time IAP (~£2.99–4.99) unlocking Journey chapters
   3–8 + cosmetic packs; everything needed to play (AI, Pass & Play, tutorial, online) free.
   Alternatives: paid upfront (~£3.99); free with rewarded (opt-in) ads only.
2. **Online in v1** — Game Center async (recommended) vs. ship local-only first and add online in 1.1.
3. **Art production** — I produce vector/procedural art in code (SwiftUI/SpriteKit shapes, SVG
   assets) for v1 with a consistent style guide, replaceable by a commissioned illustrator later;
   or you commission/hand me art; or we generate concept art with the connected Adobe/Canva tools
   and I trace/adapt it.
4. **Title** — pick one: *Oware: Seeds of Ghana* / *Ɔware* / *Oware Kingdom* / *Nana's Oware* / other.
5. **Cultural review** — do you have Ghanaian heritage or someone who can review the Heritage
   text and Twi strings? (Affects how boldly we use Twi in the UI.)
6. **Apple Developer account** — do you already have a paid account + team ID? Needed for Game
   Center, IAP and TestFlight (not for building locally).
7. **Extra variants** — Abapa only for v1 (recommended) or also Nam-Nam / Kalah?

---

## 8. Sources consulted
- https://www.oware.co.uk/ (The Oware Society — shop, rules booklets, events)
- https://www.mastersofgames.com/rules/mancala-rules.htm (Oware rules)
- http://www.oware.org/abapa.asp (Abapa rules text)
- https://www.bead.game/games/traditional/oware
- https://en.wikipedia.org/wiki/Oware
- https://ghanaculture.gov.gh/ashanti-region/ (National Commission on Culture)
- https://www.adinkrasymbols.org/ , https://en.wikipedia.org/wiki/Sankofa , https://en.wikipedia.org/wiki/Gye_Nyame_(Adinkra)
- Kente colour meanings: cultureville.co.uk, kentecloth.net, vibesghana.com
- Asante stools & gold weights: momaa.org; Atumpan/Fontomfrom: Wikipedia, tandfonline article
- Competitors: App Store listings for Awale Online, Oware Master, Awele/Oware Mancala HD, Mancala Adventures
- AI: Romein & Bal 2002 (Awari solved), chessprogramming.org/Awari
- Apple App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
